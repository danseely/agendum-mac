"""JSON-over-stdio backend helper for the Agendum Mac prototype."""

from __future__ import annotations

import asyncio
import json
import os
import shutil
import sqlite3
import subprocess
import sys
from dataclasses import dataclass, field
from datetime import datetime, timezone
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
from agendum.db import init_db, remove_task, update_task  # noqa: E402
from agendum.syncer import run_sync  # noqa: E402
from agendum.task_api import get_task as agendum_get_task  # noqa: E402
from agendum.task_api import list_tasks as agendum_list_tasks  # noqa: E402


@dataclass
class HelperState:
    base_dir: Path
    namespace: str | None = None
    sync_status: dict[str, Any] = field(default_factory=lambda: _sync_status())

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
        if command == "task.list":
            return _success_response(request_id, {"tasks": list_tasks(state, payload)})
        if command == "task.get":
            return _success_response(request_id, {"task": get_task(state, payload)})
        if command in _TASK_STATUS_COMMANDS:
            return _success_response(request_id, {"task": update_task_status(state, payload, command)})
        if command == "task.markSeen":
            return _success_response(request_id, {"task": mark_task_seen(state, payload)})
        if command == "task.remove":
            return _success_response(request_id, remove_task_command(state, payload))
        if command == "sync.status":
            return _success_response(request_id, {"status": state.sync_status})
        if command == "sync.force":
            return _success_response(request_id, {"status": force_sync(state)})
    except PayloadError as exc:
        return _error_response(
            request_id=request_id,
            code="payload.invalid",
            message=str(exc),
        )
    except TaskNotFoundError as exc:
        return _error_response(
            request_id=request_id,
            code="task.notFound",
            message="Task was not found.",
            detail=str(exc),
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
    except sqlite3.Error as exc:
        return _error_response(
            request_id=request_id,
            code="storage.failed",
            message="Task storage could not be read.",
            detail=str(exc),
        )

    return _error_response(
        request_id=request_id,
        code="protocol.unknownCommand",
        message="Unknown command.",
        detail=str(command),
    )


_TASK_STATUS_COMMANDS = {
    "task.markReviewed": "reviewed",
    "task.markInProgress": "in progress",
    "task.moveToBacklog": "backlog",
    "task.markDone": "done",
}


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
    if isinstance(namespace, str) and not namespace.strip():
        raise PayloadError("Workspace namespace must not be blank; use null for the base workspace.")

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


def list_tasks(state: HelperState, payload: dict[str, Any]) -> list[dict[str, Any]]:
    source = _optional_string(payload, "source")
    status = _optional_string(payload, "status")
    project = _optional_string(payload, "project")

    include_seen = payload.get("includeSeen", True)
    if not isinstance(include_seen, bool):
        raise PayloadError("Task includeSeen filter must be a boolean.")

    limit = payload.get("limit", 50)
    if isinstance(limit, bool) or not isinstance(limit, int):
        raise PayloadError("Task limit must be an integer.")
    if limit <= 0:
        raise PayloadError("Task limit must be greater than zero.")
    if limit > 200:
        raise PayloadError("Task limit must be <= 200.")

    paths = state.runtime
    ensure_workspace_config(paths, namespace=state.namespace)
    init_db(paths.db_path)

    tasks = agendum_list_tasks(
        paths.db_path,
        source=source,
        status=status,
        project=project,
        include_seen=include_seen,
        limit=limit,
    )
    return [_task_payload(task) for task in tasks]


def get_task(state: HelperState, payload: dict[str, Any]) -> dict[str, Any] | None:
    task_id = _task_id(payload)
    paths = _prepare_task_storage(state)
    task = agendum_get_task(paths.db_path, task_id)
    return _task_payload(task) if task else None


def update_task_status(state: HelperState, payload: dict[str, Any], command: str) -> dict[str, Any]:
    task_id = _task_id(payload)
    status = _TASK_STATUS_COMMANDS[command]
    paths = _prepare_task_storage(state)
    _require_task(paths.db_path, task_id)
    update_task(paths.db_path, task_id, status=status)
    return _task_payload(_require_task(paths.db_path, task_id))


def mark_task_seen(state: HelperState, payload: dict[str, Any]) -> dict[str, Any]:
    task_id = _task_id(payload)
    paths = _prepare_task_storage(state)
    _require_task(paths.db_path, task_id)
    update_task(
        paths.db_path,
        task_id,
        seen=1,
        last_seen_at=datetime.now(timezone.utc).isoformat(),
    )
    return _task_payload(_require_task(paths.db_path, task_id))


def remove_task_command(state: HelperState, payload: dict[str, Any]) -> dict[str, bool]:
    task_id = _task_id(payload)
    paths = _prepare_task_storage(state)
    _require_task(paths.db_path, task_id)
    remove_task(paths.db_path, task_id)
    return {"removed": True}


def force_sync(state: HelperState) -> dict[str, Any]:
    if state.sync_status["state"] == "running":
        return state.sync_status

    paths = state.runtime
    config = ensure_workspace_config(paths, namespace=state.namespace)
    init_db(paths.db_path)
    state.sync_status = {
        **state.sync_status,
        "state": "running",
        "lastError": None,
    }

    try:
        changes, has_attention_items, error_message = asyncio.run(run_sync(paths.db_path, config))
    except Exception as exc:
        state.sync_status = {
            "state": "error",
            "lastSyncAt": datetime.now(timezone.utc).isoformat(),
            "lastError": str(exc),
            "changes": 0,
            "hasAttentionItems": False,
        }
        return state.sync_status

    state.sync_status = {
        "state": "error" if error_message else "idle",
        "lastSyncAt": datetime.now(timezone.utc).isoformat(),
        "lastError": error_message,
        "changes": changes,
        "hasAttentionItems": has_attention_items,
    }
    return state.sync_status


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


def _optional_string(payload: dict[str, Any], key: str) -> str | None:
    value = payload.get(key)
    if value is None:
        return None
    if not isinstance(value, str):
        raise PayloadError(f"Task {key} filter must be a string or null.")
    return value


def _task_id(payload: dict[str, Any]) -> int:
    task_id = payload.get("id")
    if isinstance(task_id, bool) or not isinstance(task_id, int):
        raise PayloadError("Task id must be an integer.")
    if task_id <= 0:
        raise PayloadError("Task id must be greater than zero.")
    return task_id


def _prepare_task_storage(state: HelperState) -> RuntimePaths:
    paths = state.runtime
    ensure_workspace_config(paths, namespace=state.namespace)
    init_db(paths.db_path)
    return paths


def _require_task(db_path: Path, task_id: int) -> dict[str, Any]:
    task = agendum_get_task(db_path, task_id)
    if task is None:
        raise TaskNotFoundError(f"task {task_id} not found")
    return task


def _task_payload(task: dict[str, Any]) -> dict[str, Any]:
    return {
        "id": task["id"],
        "title": task["title"],
        "source": task["source"],
        "status": task["status"],
        "project": task.get("project"),
        "ghRepo": task.get("gh_repo"),
        "ghUrl": task.get("gh_url"),
        "ghNumber": task.get("gh_number"),
        "ghAuthor": task.get("gh_author"),
        "ghAuthorName": task.get("gh_author_name"),
        "tags": task.get("tags") or [],
        "seen": bool(task.get("seen", True)),
        "lastChangedAt": task.get("last_changed_at"),
        "updatedAt": task.get("updated_at"),
    }


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


class TaskNotFoundError(Exception):
    pass


def main() -> int:
    return run_stdio()


if __name__ == "__main__":
    raise SystemExit(main())
