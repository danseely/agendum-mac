from __future__ import annotations

import json
import os
import stat
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT.parent / "agendum" / "src"))

from agendum.db import add_task, init_db, update_task  # noqa: E402

HELPER = REPO_ROOT / "Backend" / "agendum_backend_helper.py"


class BackendHelperProcessTests(unittest.TestCase):
    def test_workspace_current_uses_jsonl_process_framing(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            responses = self.run_helper(
                [
                    {
                        "version": 1,
                        "id": "process-workspace",
                        "command": "workspace.current",
                        "payload": {},
                    }
                ],
                base_dir=Path(tmp),
            )

            self.assertEqual(len(responses), 1)
            response = responses[0]
            self.assertTrue(response["ok"])
            self.assertEqual(response["id"], "process-workspace")
            self.assertEqual(response["payload"]["workspace"]["configPath"], str(Path(tmp) / "config.toml"))

    def test_multiple_requests_share_one_helper_process(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            responses = self.run_helper(
                [
                    {
                        "version": 1,
                        "id": "first",
                        "command": "workspace.current",
                        "payload": {},
                    },
                    {
                        "version": 1,
                        "id": "second",
                        "command": "auth.status",
                        "payload": {},
                    },
                ],
                base_dir=Path(tmp),
                extra_env={"AGENDUM_MAC_GH_PATHS": ""},
            )

            self.assertEqual([response["id"] for response in responses], ["first", "second"])
            self.assertTrue(responses[0]["ok"])
            self.assertTrue(responses[1]["ok"])
            self.assertIn("auth", responses[1]["payload"])

    def test_malformed_input_returns_error_and_helper_continues(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            responses = self.run_helper(
                [
                    "{",
                    {
                        "version": 1,
                        "id": "after-error",
                        "command": "workspace.current",
                        "payload": {},
                    },
                ],
                base_dir=Path(tmp),
            )

            self.assertEqual(len(responses), 2)
            self.assertFalse(responses[0]["ok"])
            self.assertEqual(responses[0]["error"]["code"], "payload.invalid")
            self.assertTrue(responses[1]["ok"])
            self.assertEqual(responses[1]["id"], "after-error")

    def test_workspace_select_updates_shared_process_state_and_list(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            responses = self.run_helper(
                [
                    {
                        "version": 1,
                        "id": "select-workspace",
                        "command": "workspace.select",
                        "payload": {"namespace": "Example-Org"},
                    },
                    {
                        "version": 1,
                        "id": "current-workspace",
                        "command": "workspace.current",
                        "payload": {},
                    },
                    {
                        "version": 1,
                        "id": "list-workspaces",
                        "command": "workspace.list",
                        "payload": {},
                    },
                ],
                base_dir=root,
            )

            selected = responses[0]["payload"]["workspace"]
            current = responses[1]["payload"]["workspace"]
            listed = responses[2]["payload"]["workspaces"]

            self.assertTrue(all(response["ok"] for response in responses))
            self.assertEqual(selected["id"], "example-org")
            self.assertEqual(current["id"], "example-org")
            self.assertTrue((root / "workspaces" / "example-org" / "config.toml").exists())
            self.assertEqual([workspace["id"] for workspace in listed], ["base", "example-org"])
            self.assertFalse(listed[0]["isCurrent"])
            self.assertTrue(listed[1]["isCurrent"])

    def test_workspace_select_invalid_namespace_keeps_shared_process_on_base(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            responses = self.run_helper(
                [
                    {
                        "version": 1,
                        "id": "bad-select",
                        "command": "workspace.select",
                        "payload": {"namespace": "owner/repo"},
                    },
                    {
                        "version": 1,
                        "id": "current-after-bad-select",
                        "command": "workspace.current",
                        "payload": {},
                    },
                ],
                base_dir=root,
            )

            self.assertFalse(responses[0]["ok"])
            self.assertEqual(responses[0]["error"]["code"], "workspace.invalid")
            self.assertTrue(responses[1]["ok"])
            self.assertEqual(responses[1]["payload"]["workspace"]["id"], "base")
            self.assertFalse((root / "workspaces").exists())

    def test_task_list_uses_jsonl_process_framing(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            db_path = root / "agendum.db"
            init_db(db_path)
            task_id = add_task(
                db_path,
                title="Process task",
                source="issue",
                status="open",
                project="agendum-mac",
                gh_repo="danseely/agendum-mac",
                gh_url="https://github.com/danseely/agendum-mac/issues/8",
                gh_number=8,
            )
            update_task(db_path, task_id, seen=0)

            responses = self.run_helper(
                [
                    {
                        "version": 1,
                        "id": "process-task-list",
                        "command": "task.list",
                        "payload": {"includeSeen": False},
                    }
                ],
                base_dir=root,
            )

            self.assertEqual(len(responses), 1)
            response = responses[0]
            self.assertTrue(response["ok"])
            self.assertEqual(response["id"], "process-task-list")
            self.assertEqual(response["payload"]["tasks"][0]["title"], "Process task")
            self.assertEqual(response["payload"]["tasks"][0]["ghNumber"], 8)
            self.assertFalse(response["payload"]["tasks"][0]["seen"])

    def test_task_actions_use_jsonl_process_framing(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            db_path = root / "agendum.db"
            init_db(db_path)
            task_id = add_task(
                db_path,
                title="Process action task",
                source="manual",
                status="backlog",
                project="agendum-mac",
            )

            responses = self.run_helper(
                [
                    {
                        "version": 1,
                        "id": "process-task-get",
                        "command": "task.get",
                        "payload": {"id": task_id},
                    },
                    {
                        "version": 1,
                        "id": "process-task-done",
                        "command": "task.markDone",
                        "payload": {"id": task_id},
                    },
                    {
                        "version": 1,
                        "id": "process-task-remove",
                        "command": "task.remove",
                        "payload": {"id": task_id},
                    },
                ],
                base_dir=root,
            )

            self.assertEqual(len(responses), 3)
            self.assertTrue(all(response["ok"] for response in responses))
            self.assertEqual(responses[0]["payload"]["task"]["title"], "Process action task")
            self.assertEqual(responses[1]["payload"]["task"]["status"], "done")
            self.assertTrue(responses[2]["payload"]["removed"])

    def test_task_create_manual_persists_through_jsonl_process(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)

            responses = self.run_helper(
                [
                    {
                        "version": 1,
                        "id": "process-create-manual",
                        "command": "task.createManual",
                        "payload": {
                            "title": "Process manual task",
                            "project": "agendum-mac",
                            "tags": ["planning"],
                        },
                    },
                    {
                        "version": 1,
                        "id": "process-create-manual-list",
                        "command": "task.list",
                        "payload": {},
                    },
                    {
                        "version": 1,
                        "id": "process-create-manual-bad",
                        "command": "task.createManual",
                        "payload": {"title": "   "},
                    },
                ],
                base_dir=root,
            )

            self.assertEqual(len(responses), 3)
            self.assertTrue(responses[0]["ok"])
            created = responses[0]["payload"]["task"]
            self.assertEqual(created["title"], "Process manual task")
            self.assertEqual(created["source"], "manual")
            self.assertEqual(created["status"], "backlog")
            self.assertEqual(created["tags"], ["planning"])

            self.assertTrue(responses[1]["ok"])
            listed = responses[1]["payload"]["tasks"]
            self.assertEqual(len(listed), 1)
            self.assertEqual(listed[0]["id"], created["id"])
            self.assertEqual(listed[0]["title"], "Process manual task")

            self.assertFalse(responses[2]["ok"])
            self.assertEqual(responses[2]["error"]["code"], "payload.invalid")

    def test_sync_force_and_status_use_shared_jsonl_process(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            env = os.environ.copy()
            env["AGENDUM_MAC_BASE_DIR"] = str(root)
            process = subprocess.Popen(
                [sys.executable, str(HELPER)],
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                env=env,
                cwd=REPO_ROOT,
            )

            def request(command: str, request_id: str) -> dict[str, Any]:
                self.assertIsNotNone(process.stdin)
                self.assertIsNotNone(process.stdout)
                process.stdin.write(
                    json.dumps(
                        {
                            "version": 1,
                            "id": request_id,
                            "command": command,
                            "payload": {},
                        }
                    )
                    + "\n"
                )
                process.stdin.flush()
                line = process.stdout.readline()
                self.assertNotEqual(line, "", "helper exited before returning a response")
                return json.loads(line)

            try:
                forced = request("sync.force", "process-sync-force")
                self.assertTrue(forced["ok"])
                self.assertEqual(forced["payload"]["status"]["state"], "running")

                deadline = time.monotonic() + 5
                status = forced["payload"]["status"]
                while time.monotonic() < deadline:
                    response = request("sync.status", "process-sync-status")
                    self.assertTrue(response["ok"])
                    status = response["payload"]["status"]
                    if status["state"] != "running":
                        break
                    time.sleep(0.01)

                self.assertEqual(status["state"], "idle")
                self.assertEqual(status["changes"], 0)
                self.assertFalse(status["hasAttentionItems"])
                self.assertIsNotNone(status["lastSyncAt"])
            finally:
                if process.stdin:
                    process.stdin.close()
                stderr = process.stderr.read() if process.stderr else ""
                process.wait(timeout=5)
                if process.stdout:
                    process.stdout.close()
                if process.stderr:
                    process.stderr.close()
                self.assertEqual(process.returncode, 0, stderr)

    def test_auth_diagnose_round_trips_through_jsonl_process(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            responses = self.run_helper(
                [
                    {
                        "version": 1,
                        "id": "process-diagnose",
                        "command": "auth.diagnose",
                        "payload": {},
                    }
                ],
                base_dir=Path(tmp),
                extra_env={"AGENDUM_MAC_GH_PATHS": ""},
            )

            self.assertEqual(len(responses), 1)
            response = responses[0]
            self.assertTrue(response["ok"])
            self.assertNotEqual(response.get("error", {}).get("code"), "payload.invalid")
            diagnostics = response["payload"]["diagnostics"]
            self.assertIn("gh", diagnostics)
            self.assertIn("helperPath", diagnostics)
            self.assertIsInstance(diagnostics["helperPath"], list)

    def test_process_honors_base_dir_and_configured_gh_path(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            base_dir = root / "agendum"
            fake_gh = root / "gh"
            expected_config_dir = base_dir / "gh"
            fake_gh.write_text(
                "#!/bin/sh\n"
                f"if [ \"$GH_CONFIG_DIR\" != \"{expected_config_dir}\" ]; then exit 2; fi\n"
                "if [ \"$1 $2\" = \"auth status\" ]; then exit 0; fi\n"
                "if [ \"$1 $2 $3 $4\" = \"api user --jq .login\" ]; then echo dan; exit 0; fi\n"
                "exit 1\n"
            )
            fake_gh.chmod(fake_gh.stat().st_mode | stat.S_IXUSR)

            responses = self.run_helper(
                [
                    {
                        "version": 1,
                        "id": "process-auth",
                        "command": "auth.status",
                        "payload": {},
                    }
                ],
                base_dir=base_dir,
                extra_env={"AGENDUM_MAC_GH_PATHS": str(fake_gh), "PATH": ""},
            )

            auth = responses[0]["payload"]["auth"]
            self.assertTrue(responses[0]["ok"])
            self.assertTrue(auth["authenticated"])
            self.assertEqual(auth["ghPath"], str(fake_gh))
            self.assertEqual(auth["username"], "dan")
            self.assertEqual(auth["workspaceGhConfigDir"], str(expected_config_dir))

    def run_helper(
        self,
        requests: list[dict[str, Any] | str],
        *,
        base_dir: Path,
        extra_env: dict[str, str] | None = None,
    ) -> list[dict[str, Any]]:
        env = os.environ.copy()
        env["AGENDUM_MAC_BASE_DIR"] = str(base_dir)
        if extra_env:
            env.update(extra_env)

        input_text = "\n".join(
            request if isinstance(request, str) else json.dumps(request)
            for request in requests
        )
        process = subprocess.run(
            [sys.executable, str(HELPER)],
            input=input_text + "\n",
            capture_output=True,
            text=True,
            env=env,
            cwd=REPO_ROOT,
            check=False,
            timeout=5,
        )

        self.assertEqual(process.returncode, 0, process.stderr)
        return [json.loads(line) for line in process.stdout.splitlines()]


if __name__ == "__main__":
    unittest.main()
