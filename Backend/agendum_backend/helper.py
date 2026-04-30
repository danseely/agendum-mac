"""JSON-over-stdio backend helper for the Agendum Mac prototype."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, TextIO

PROTOCOL_VERSION = 1
BASE_DIR_ENV = "AGENDUM_MAC_BASE_DIR"
GH_PATHS_ENV = "AGENDUM_MAC_GH_PATHS"


def _bootstrap_agendum_import() -> None:
    repo_root = Path(__file__).resolve().parents[2]
    sibling_src = repo_root.parent / "agendum" / "src"
    if sibling_src.exists():
        sys.path.insert(0, str(sibling_src))


_bootstrap_agendum_import()

from agendum.config import (  # noqa: E402
    RuntimePaths,
    ensure_workspace_config,
    normalize_namespace,
    workspace_runtime_paths,
)


@dataclass
class HelperState:
    base_dir: Path
    namespace: str | None = None

    @classmethod
    def from_environment(cls) -> "HelperState":
        base_dir = Path(os.environ.get(BASE_DIR_ENV, Path.home() / ".agendum")).expanduser()
        return cls(base_dir=base_dir)

    @property
    def runtime(self) -> RuntimePaths:
        return workspace_runtime_paths(self.namespace, self.base_dir)


def run_stdio(stdin: TextIO = sys.stdin, stdout: TextIO = sys.stdout) -> int:
    state = HelperState.from_environment()
    for line in stdin:
        line = line.strip()
        if not line:
            continue
        response = handle_line(line, state)
        stdout.write(json.dumps(response, separators=(",", ":")) + "\n")
        stdout.flush()
    return 0


def handle_line(line: str, state: HelperState) -> dict[str, Any]:
    try:
        request = json.loads(line)
    except json.JSONDecodeError as exc:
        return _error_response(
            request_id=None,
            code="payload.invalid",
            message="Request is not valid JSON.",
            detail=str(exc),
        )
    return handle_request(request, state)


def handle_request(request: Any, state: HelperState) -> dict[str, Any]:
    if not isinstance(request, dict):
        return _error_response(
            request_id=None,
            code="payload.invalid",
            message="Request envelope must be an object.",
        )

    request_id = request.get("id")
    if request.get("version") != PROTOCOL_VERSION:
        return _error_response(
            request_id=request_id,
            code="protocol.unsupportedVersion",
            message="Unsupported protocol version.",
            detail=f"Expected version {PROTOCOL_VERSION}.",
        )

    payload = request.get("payload", {})
    if not isinstance(payload, dict):
        return _error_response(
            request_id=request_id,
            code="payload.invalid",
            message="Request payload must be an object.",
        )

    command = request.get("command")
    try:
        if command == "workspace.current":
            return _success_response(request_id, {"workspace": current_workspace(state)})
        if command == "workspace.list":
            return _success_response(request_id, {"workspaces": list_workspaces(state)})
        if command == "workspace.select":
            return _success_response(request_id, select_workspace(state, payload))
        if command == "auth.status":
            return _success_response(request_id, {"auth": auth_status(state)})
    except PayloadError as exc:
        return _error_response(
            request_id=request_id,
            code="payload.invalid",
            message=str(exc),
        )
    except ValueError as exc:
        return _error_response(
            request_id=request_id,
            code="workspace.invalid",
            message="Workspace is invalid.",
            detail=str(exc),
        )
    except OSError as exc:
        return _error_response(
            request_id=request_id,
            code="storage.failed",
            message="Workspace storage could not be prepared.",
            detail=str(exc),
        )

    return _error_response(
        request_id=request_id,
        code="protocol.unknownCommand",
        message="Unknown command.",
        detail=str(command),
    )


def current_workspace(state: HelperState) -> dict[str, Any]:
    paths = state.runtime
    ensure_workspace_config(paths, namespace=state.namespace)
    return _workspace_payload(paths, state.namespace, is_current=True)


def list_workspaces(state: HelperState) -> list[dict[str, Any]]:
    workspaces = [
        _workspace_payload(
            workspace_runtime_paths(None, state.base_dir),
            None,
            is_current=state.namespace is None,
        )
    ]

    workspaces_dir = state.base_dir / "workspaces"
    if not workspaces_dir.exists():
        return workspaces

    for child in sorted(workspaces_dir.iterdir(), key=lambda path: path.name.lower()):
        if not child.is_dir():
            continue
        namespace = child.name
        try:
            paths = workspace_runtime_paths(namespace, state.base_dir)
        except ValueError:
            continue
        workspaces.append(
            _workspace_payload(
                paths,
                namespace,
                is_current=namespace == state.namespace,
            )
        )
    return workspaces


def select_workspace(state: HelperState, payload: dict[str, Any]) -> dict[str, Any]:
    if "namespace" not in payload:
        raise PayloadError("Workspace selection requires a namespace field.")

    namespace = payload["namespace"]
    if namespace is not None and not isinstance(namespace, str):
        raise PayloadError("Workspace namespace must be a string or null.")

    normalized = normalize_namespace(namespace)
    paths = workspace_runtime_paths(normalized, state.base_dir)
    effective_namespace = None
    if normalized is not None:
        effective_namespace = paths.workspace_root.name

    ensure_workspace_config(paths, namespace=normalized)
    state.namespace = effective_namespace
    return {
        "workspace": _workspace_payload(paths, state.namespace, is_current=True),
        "auth": auth_status(state),
        "sync": _sync_status(),
    }


def auth_status(state: HelperState) -> dict[str, Any]:
    paths = state.runtime
    ensure_workspace_config(paths, namespace=state.namespace)
    gh_path = _find_gh()
    if gh_path is None:
        return {
            "ghFound": False,
            "ghPath": None,
            "authenticated": False,
            "username": None,
            "workspaceGhConfigDir": _display_path(paths.gh_config_dir),
            "repairInstructions": "Install GitHub CLI with Homebrew, then authenticate with gh auth login.",
        }

    env = os.environ.copy()
    env["GH_CONFIG_DIR"] = str(paths.gh_config_dir)
    auth = subprocess.run(
        [str(gh_path), "auth", "status"],
        capture_output=True,
        text=True,
        env=env,
        check=False,
    )
    if auth.returncode != 0:
        return {
            "ghFound": True,
            "ghPath": str(gh_path),
            "authenticated": False,
            "username": None,
            "workspaceGhConfigDir": _display_path(paths.gh_config_dir),
            "repairInstructions": f"Run GH_CONFIG_DIR={paths.gh_config_dir} gh auth login in Terminal.",
        }

    return {
        "ghFound": True,
        "ghPath": str(gh_path),
        "authenticated": True,
        "username": _gh_username(gh_path, env),
        "workspaceGhConfigDir": _display_path(paths.gh_config_dir),
        "repairInstructions": None,
    }


def _find_gh() -> Path | None:
    candidates: list[str] = []
    if configured_paths := os.environ.get(GH_PATHS_ENV):
        candidates.extend(path for path in configured_paths.split(os.pathsep) if path)
    candidates.extend(
        [
            "/opt/homebrew/bin/gh",
            "/usr/local/bin/gh",
            "/usr/bin/gh",
        ]
    )
    if path_gh := shutil.which("gh"):
        candidates.append(path_gh)

    seen: set[Path] = set()
    for candidate in candidates:
        path = Path(candidate).expanduser()
        if path in seen:
            continue
        seen.add(path)
        if path.is_file() and os.access(path, os.X_OK):
            return path
    return None


def _gh_username(gh_path: Path, env: dict[str, str]) -> str | None:
    result = subprocess.run(
        [str(gh_path), "api", "user", "--jq", ".login"],
        capture_output=True,
        text=True,
        env=env,
        check=False,
    )
    if result.returncode != 0:
        return None
    username = result.stdout.strip()
    return username or None


def _workspace_payload(
    paths: RuntimePaths,
    namespace: str | None,
    *,
    is_current: bool,
) -> dict[str, Any]:
    return {
        "id": namespace or "base",
        "namespace": namespace,
        "displayName": namespace or "Base Workspace",
        "configPath": _display_path(paths.config_path),
        "dbPath": _display_path(paths.db_path),
        "isCurrent": is_current,
    }


def _sync_status() -> dict[str, Any]:
    return {
        "state": "idle",
        "lastSyncAt": None,
        "lastError": None,
        "changes": 0,
        "hasAttentionItems": False,
    }


def _display_path(path: Path) -> str:
    home = Path.home()
    try:
        return "~/" + str(path.expanduser().relative_to(home))
    except ValueError:
        return str(path)


def _success_response(request_id: Any, payload: dict[str, Any]) -> dict[str, Any]:
    return {
        "version": PROTOCOL_VERSION,
        "id": request_id,
        "ok": True,
        "payload": payload,
    }


def _error_response(
    *,
    request_id: Any,
    code: str,
    message: str,
    detail: str | None = None,
    recovery: str | None = None,
) -> dict[str, Any]:
    error: dict[str, Any] = {
        "code": code,
        "message": message,
    }
    if detail:
        error["detail"] = detail
    if recovery:
        error["recovery"] = recovery
    return {
        "version": PROTOCOL_VERSION,
        "id": request_id,
        "ok": False,
        "error": error,
    }


class PayloadError(ValueError):
    pass


def main() -> int:
    return run_stdio()


if __name__ == "__main__":
    raise SystemExit(main())
