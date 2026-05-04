from __future__ import annotations

import asyncio
import json
import os
import stat
import subprocess
import tempfile
import time
import unittest
from io import StringIO
from pathlib import Path
from unittest import mock

from Backend.agendum_backend.helper import (
    HelperState,
    _format_repair_command,
    _gh_version,
    auth_status,
    handle_line,
    handle_request,
    run_stdio,
)
from agendum.db import add_task, init_db, update_task


def wait_for_sync_state(state: HelperState, expected: str) -> dict:
    deadline = time.monotonic() + 2
    while time.monotonic() < deadline:
        response = handle_request(
            {
                "version": 1,
                "id": "wait-sync-status",
                "command": "sync.status",
                "payload": {},
            },
            state,
        )
        status = response["payload"]["status"]
        if status["state"] == expected:
            return status
        time.sleep(0.01)
    self_status = handle_request(
        {
            "version": 1,
            "id": "wait-sync-status-final",
            "command": "sync.status",
            "payload": {},
        },
        state,
    )
    raise AssertionError(f"Timed out waiting for sync state {expected}: {self_status}")


class BackendHelperTests(unittest.TestCase):
    def test_run_stdio_processes_jsonl_and_skips_blank_lines(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            request = {
                "version": 1,
                "id": "stdio-workspace",
                "command": "workspace.current",
                "payload": {},
            }
            stdout = StringIO()

            with mock.patch.dict(os.environ, {"AGENDUM_MAC_BASE_DIR": tmp}, clear=False):
                exit_code = run_stdio(StringIO("\n" + json.dumps(request) + "\n"), stdout)

            self.assertEqual(exit_code, 0)
            responses = [json.loads(line) for line in stdout.getvalue().splitlines()]
            self.assertEqual(len(responses), 1)
            self.assertTrue(responses[0]["ok"])
            self.assertEqual(responses[0]["id"], "stdio-workspace")
            self.assertEqual(responses[0]["payload"]["workspace"]["configPath"], str(Path(tmp) / "config.toml"))

    def test_workspace_current_creates_base_config_and_returns_contract_payload(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            state = HelperState(base_dir=Path(tmp))
            response = handle_request(
                {
                    "version": 1,
                    "id": "req-1",
                    "command": "workspace.current",
                    "payload": {},
                },
                state,
            )

            self.assertTrue(response["ok"])
            workspace = response["payload"]["workspace"]
            self.assertEqual(workspace["id"], "base")
            self.assertIsNone(workspace["namespace"])
            self.assertEqual(workspace["displayName"], "Base Workspace")
            self.assertEqual(workspace["configPath"], str(Path(tmp) / "config.toml"))
            self.assertEqual(workspace["dbPath"], str(Path(tmp) / "agendum.db"))
            self.assertTrue(workspace["isCurrent"])
            self.assertTrue((Path(tmp) / "config.toml").exists())

    def test_workspace_list_includes_base_and_existing_namespaces(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "workspaces" / "example-org").mkdir(parents=True)
            (root / "workspaces" / "z-team").mkdir()
            (root / "workspaces" / "invalid--name").mkdir()
            (root / "workspaces" / "not-a-dir").write_text("")

            response = handle_request(
                {
                    "version": 1,
                    "id": "workspace-list",
                    "command": "workspace.list",
                    "payload": {},
                },
                HelperState(base_dir=root, namespace="z-team"),
            )

            self.assertTrue(response["ok"])
            workspaces = response["payload"]["workspaces"]
            self.assertEqual([workspace["id"] for workspace in workspaces], ["base", "example-org", "z-team"])
            self.assertFalse(workspaces[0]["isCurrent"])
            self.assertFalse(workspaces[1]["isCurrent"])
            self.assertTrue(workspaces[2]["isCurrent"])
            self.assertEqual(workspaces[1]["configPath"], str(root / "workspaces" / "example-org" / "config.toml"))

    def test_workspace_select_creates_namespace_config_and_updates_current_state(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            state = HelperState(base_dir=root)

            with mock.patch("Backend.agendum_backend.helper._find_gh", return_value=None):
                response = handle_request(
                    {
                        "version": 1,
                        "id": "workspace-select",
                        "command": "workspace.select",
                        "payload": {"namespace": "Example-Org"},
                    },
                    state,
                )

            self.assertTrue(response["ok"])
            workspace = response["payload"]["workspace"]
            self.assertEqual(workspace["id"], "example-org")
            self.assertEqual(workspace["namespace"], "example-org")
            self.assertTrue(workspace["isCurrent"])
            self.assertEqual(workspace["configPath"], str(root / "workspaces" / "example-org" / "config.toml"))
            self.assertEqual(response["payload"]["sync"]["state"], "idle")
            self.assertIn('orgs = ["Example-Org"]', (root / "workspaces" / "example-org" / "config.toml").read_text())
            self.assertEqual(state.namespace, "example-org")

            current = handle_request(
                {
                    "version": 1,
                    "id": "workspace-current-after-select",
                    "command": "workspace.current",
                    "payload": {},
                },
                state,
            )
            self.assertEqual(current["payload"]["workspace"]["id"], "example-org")

    def test_workspace_select_null_returns_to_base_workspace(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            state = HelperState(base_dir=root, namespace="example-org")

            with mock.patch("Backend.agendum_backend.helper._find_gh", return_value=None):
                response = handle_request(
                    {
                        "version": 1,
                        "id": "workspace-select-base",
                        "command": "workspace.select",
                        "payload": {"namespace": None},
                    },
                    state,
                )

            self.assertTrue(response["ok"])
            self.assertEqual(response["payload"]["workspace"]["id"], "base")
            self.assertIsNone(response["payload"]["workspace"]["namespace"])
            self.assertIsNone(state.namespace)
            self.assertTrue((root / "config.toml").exists())

    def test_workspace_select_rejects_bad_payload_without_changing_workspace(self) -> None:
        state = HelperState(base_dir=Path("/tmp/agendum-test"), namespace="example-org")

        for payload in ({}, {"namespace": 42}, {"namespace": "   "}):
            with self.subTest(payload=payload):
                response = handle_request(
                    {
                        "version": 1,
                        "id": "bad-workspace-select",
                        "command": "workspace.select",
                        "payload": payload,
                    },
                    state,
                )

                self.assertFalse(response["ok"])
                self.assertEqual(response["error"]["code"], "payload.invalid")
                self.assertEqual(state.namespace, "example-org")

    def test_workspace_select_rejects_invalid_namespace_without_changing_workspace(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            state = HelperState(base_dir=Path(tmp), namespace="example-org")
            response = handle_request(
                {
                    "version": 1,
                    "id": "invalid-workspace-select",
                    "command": "workspace.select",
                    "payload": {"namespace": "owner/repo"},
                },
                state,
            )

            self.assertFalse(response["ok"])
            self.assertEqual(response["error"]["code"], "workspace.invalid")
            self.assertEqual(state.namespace, "example-org")
            self.assertFalse((Path(tmp) / "workspaces").exists())

    def test_task_list_returns_contract_payload_and_filters(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            db_path = root / "agendum.db"
            init_db(db_path)
            review_id = add_task(
                db_path,
                title="Review release workflow hardening",
                source="pr_review",
                status="review requested",
                project="homebrew-tap",
                gh_repo="danseely/homebrew-tap",
                gh_url="https://github.com/danseely/homebrew-tap/pull/17",
                gh_number=17,
                gh_author="octocat",
                gh_author_name="Octo",
                tags=json.dumps(["review", "release"]),
            )
            update_task(db_path, review_id, seen=0)
            add_task(
                db_path,
                title="Hidden authored PR",
                source="pr_authored",
                status="open",
                project="agendum",
            )

            response = handle_request(
                {
                    "version": 1,
                    "id": "task-list",
                    "command": "task.list",
                    "payload": {"source": "pr_review", "includeSeen": False, "limit": 5},
                },
                HelperState(base_dir=root),
            )

            self.assertTrue(response["ok"])
            tasks = response["payload"]["tasks"]
            self.assertEqual(len(tasks), 1)
            task = tasks[0]
            self.assertEqual(task["id"], review_id)
            self.assertEqual(task["title"], "Review release workflow hardening")
            self.assertEqual(task["source"], "pr_review")
            self.assertEqual(task["status"], "review requested")
            self.assertEqual(task["project"], "homebrew-tap")
            self.assertEqual(task["ghRepo"], "danseely/homebrew-tap")
            self.assertEqual(task["ghUrl"], "https://github.com/danseely/homebrew-tap/pull/17")
            self.assertEqual(task["ghNumber"], 17)
            self.assertEqual(task["ghAuthor"], "octocat")
            self.assertEqual(task["ghAuthorName"], "Octo")
            self.assertEqual(task["tags"], ["review", "release"])
            self.assertFalse(task["seen"])
            self.assertIsNotNone(task["lastChangedAt"])
            self.assertIsNotNone(task["updatedAt"])

    def test_task_list_default_payload_initializes_empty_workspace(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)

            response = handle_request(
                {
                    "version": 1,
                    "id": "task-list-defaults",
                    "command": "task.list",
                    "payload": {},
                },
                HelperState(base_dir=root),
            )

            self.assertTrue(response["ok"])
            self.assertEqual(response["payload"]["tasks"], [])
            self.assertTrue((root / "config.toml").exists())
            self.assertTrue((root / "agendum.db").exists())

    def test_task_list_maps_optional_task_fields_to_nulls_and_empty_tags(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            db_path = root / "agendum.db"
            init_db(db_path)
            task_id = add_task(
                db_path,
                title="Manual backlog task",
                source="manual",
                status="backlog",
            )

            response = handle_request(
                {
                    "version": 1,
                    "id": "task-list-null-fields",
                    "command": "task.list",
                    "payload": {},
                },
                HelperState(base_dir=root),
            )

            self.assertTrue(response["ok"])
            task = response["payload"]["tasks"][0]
            self.assertEqual(task["id"], task_id)
            self.assertIsNone(task["project"])
            self.assertIsNone(task["ghRepo"])
            self.assertIsNone(task["ghUrl"])
            self.assertIsNone(task["ghNumber"])
            self.assertIsNone(task["ghAuthor"])
            self.assertIsNone(task["ghAuthorName"])
            self.assertEqual(task["tags"], [])
            self.assertTrue(task["seen"])

    def test_task_list_applies_status_project_and_limit_filters(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            db_path = root / "agendum.db"
            init_db(db_path)
            first_id = add_task(
                db_path,
                title="First matching task",
                source="issue",
                status="open",
                project="agendum-mac",
            )
            second_id = add_task(
                db_path,
                title="Second matching task",
                source="issue",
                status="open",
                project="agendum-mac",
            )
            add_task(
                db_path,
                title="Different project task",
                source="issue",
                status="open",
                project="other",
            )
            add_task(
                db_path,
                title="Different status task",
                source="issue",
                status="in progress",
                project="agendum-mac",
            )

            response = handle_request(
                {
                    "version": 1,
                    "id": "task-list-filtered",
                    "command": "task.list",
                    "payload": {"status": "open", "project": "agendum-mac", "limit": 1},
                },
                HelperState(base_dir=root),
            )

            self.assertTrue(response["ok"])
            tasks = response["payload"]["tasks"]
            self.assertEqual(len(tasks), 1)
            self.assertIn(tasks[0]["id"], {first_id, second_id})
            self.assertEqual(tasks[0]["status"], "open")
            self.assertEqual(tasks[0]["project"], "agendum-mac")

    def test_task_list_uses_selected_workspace_database(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            namespace_db = root / "workspaces" / "example-org" / "agendum.db"
            init_db(namespace_db)
            add_task(
                namespace_db,
                title="Namespaced task",
                source="manual",
                status="backlog",
                project="example-org",
            )

            response = handle_request(
                {
                    "version": 1,
                    "id": "task-list-namespace",
                    "command": "task.list",
                    "payload": {},
                },
                HelperState(base_dir=root, namespace="example-org"),
            )

            self.assertTrue(response["ok"])
            self.assertEqual([task["title"] for task in response["payload"]["tasks"]], ["Namespaced task"])

    def test_task_list_rejects_invalid_filters(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            state = HelperState(base_dir=root)

            for payload in (
                {"source": 42},
                {"status": 42},
                {"project": 42},
                {"includeSeen": "yes"},
                {"limit": True},
                {"limit": 0},
                {"limit": 201},
            ):
                with self.subTest(payload=payload):
                    response = handle_request(
                        {
                            "version": 1,
                            "id": "bad-task-list",
                            "command": "task.list",
                            "payload": payload,
                        },
                        state,
                    )

                    self.assertFalse(response["ok"])
                    self.assertEqual(response["error"]["code"], "payload.invalid")
                    self.assertFalse((root / "config.toml").exists())
                    self.assertFalse((root / "agendum.db").exists())

    def test_task_get_returns_task_or_null(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            db_path = root / "agendum.db"
            init_db(db_path)
            task_id = add_task(
                db_path,
                title="Loaded task",
                source="manual",
                status="backlog",
            )

            found = handle_request(
                {
                    "version": 1,
                    "id": "task-get",
                    "command": "task.get",
                    "payload": {"id": task_id},
                },
                HelperState(base_dir=root),
            )
            missing = handle_request(
                {
                    "version": 1,
                    "id": "task-get-missing",
                    "command": "task.get",
                    "payload": {"id": task_id + 1},
                },
                HelperState(base_dir=root),
            )

            self.assertTrue(found["ok"])
            self.assertEqual(found["payload"]["task"]["title"], "Loaded task")
            self.assertTrue(missing["ok"])
            self.assertIsNone(missing["payload"]["task"])

    def test_task_create_manual_persists_task_and_returns_payload(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            state = HelperState(base_dir=root)

            response = handle_request(
                {
                    "version": 1,
                    "id": "create-manual",
                    "command": "task.createManual",
                    "payload": {
                        "title": "  Sketch Mac backend contract  ",
                        "project": "agendum-mac",
                        "tags": ["planning", "design"],
                    },
                },
                state,
            )

            self.assertTrue(response["ok"])
            task = response["payload"]["task"]
            self.assertEqual(task["title"], "Sketch Mac backend contract")
            self.assertEqual(task["source"], "manual")
            self.assertEqual(task["status"], "backlog")
            self.assertEqual(task["project"], "agendum-mac")
            self.assertEqual(task["tags"], ["planning", "design"])
            self.assertIsNone(task["ghUrl"])
            self.assertIsInstance(task["id"], int)

            listed = handle_request(
                {
                    "version": 1,
                    "id": "after-create",
                    "command": "task.list",
                    "payload": {},
                },
                state,
            )
            self.assertTrue(listed["ok"])
            self.assertEqual(len(listed["payload"]["tasks"]), 1)
            self.assertEqual(listed["payload"]["tasks"][0]["id"], task["id"])
            self.assertEqual(listed["payload"]["tasks"][0]["title"], "Sketch Mac backend contract")

    def test_task_create_manual_accepts_minimal_payload(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            response = handle_request(
                {
                    "version": 1,
                    "id": "create-manual-minimal",
                    "command": "task.createManual",
                    "payload": {"title": "Minimal task"},
                },
                HelperState(base_dir=Path(tmp)),
            )

            self.assertTrue(response["ok"])
            task = response["payload"]["task"]
            self.assertEqual(task["title"], "Minimal task")
            self.assertEqual(task["source"], "manual")
            self.assertEqual(task["status"], "backlog")
            self.assertIsNone(task["project"])
            self.assertEqual(task["tags"], [])

    def test_task_create_manual_uses_selected_workspace_database(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            state = HelperState(base_dir=root, namespace="example-org")

            response = handle_request(
                {
                    "version": 1,
                    "id": "create-manual-namespace",
                    "command": "task.createManual",
                    "payload": {"title": "Namespaced manual task"},
                },
                state,
            )

            self.assertTrue(response["ok"])
            task = response["payload"]["task"]
            self.assertEqual(task["title"], "Namespaced manual task")

            namespace_db = root / "workspaces" / "example-org" / "agendum.db"
            self.assertTrue(namespace_db.exists())
            base_db = root / "agendum.db"
            self.assertFalse(base_db.exists())

    def test_task_create_manual_rejects_invalid_payloads(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            state = HelperState(base_dir=Path(tmp))

            cases = [
                ({}, "Manual task title is required."),
                ({"title": 42}, "Manual task title must be a string."),
                ({"title": "   "}, "Manual task title must not be blank."),
                ({"title": "ok", "project": ""}, "Manual task project must not be blank when provided."),
                ({"title": "ok", "project": 7}, "Manual task project must be a string or null."),
                ({"title": "ok", "tags": "planning"}, "Manual task tags must be a list of strings or null."),
                ({"title": "ok", "tags": ["planning", 5]}, "Manual task tags must be a list of strings or null."),
                ({"title": "ok", "tags": ["planning", "  "]}, "Manual task tags must not contain blank strings."),
            ]

            for payload, expected_message in cases:
                with self.subTest(payload=payload):
                    response = handle_request(
                        {
                            "version": 1,
                            "id": "bad-create-manual",
                            "command": "task.createManual",
                            "payload": payload,
                        },
                        state,
                    )
                    self.assertFalse(response["ok"], msg=str(payload))
                    self.assertEqual(response["error"]["code"], "payload.invalid")
                    self.assertEqual(response["error"]["message"], expected_message)

    def test_task_actions_update_or_remove_task(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            db_path = root / "agendum.db"
            init_db(db_path)
            review_id = add_task(
                db_path,
                title="Review task",
                source="pr_review",
                status="review requested",
            )
            manual_id = add_task(
                db_path,
                title="Manual task",
                source="manual",
                status="backlog",
            )
            update_task(db_path, manual_id, seen=0)
            state = HelperState(base_dir=root)

            reviewed = handle_request(
                {
                    "version": 1,
                    "id": "mark-reviewed",
                    "command": "task.markReviewed",
                    "payload": {"id": review_id},
                },
                state,
            )
            in_progress = handle_request(
                {
                    "version": 1,
                    "id": "mark-in-progress",
                    "command": "task.markInProgress",
                    "payload": {"id": manual_id},
                },
                state,
            )
            backlog = handle_request(
                {
                    "version": 1,
                    "id": "move-backlog",
                    "command": "task.moveToBacklog",
                    "payload": {"id": manual_id},
                },
                state,
            )
            seen = handle_request(
                {
                    "version": 1,
                    "id": "mark-seen",
                    "command": "task.markSeen",
                    "payload": {"id": manual_id},
                },
                state,
            )
            done = handle_request(
                {
                    "version": 1,
                    "id": "mark-done",
                    "command": "task.markDone",
                    "payload": {"id": manual_id},
                },
                state,
            )
            removed = handle_request(
                {
                    "version": 1,
                    "id": "remove-task",
                    "command": "task.remove",
                    "payload": {"id": review_id},
                },
                state,
            )

            self.assertTrue(reviewed["ok"])
            self.assertEqual(reviewed["payload"]["task"]["status"], "reviewed")
            self.assertTrue(in_progress["ok"])
            self.assertEqual(in_progress["payload"]["task"]["status"], "in progress")
            self.assertTrue(backlog["ok"])
            self.assertEqual(backlog["payload"]["task"]["status"], "backlog")
            self.assertTrue(seen["ok"])
            self.assertTrue(seen["payload"]["task"]["seen"])
            self.assertTrue(done["ok"])
            self.assertEqual(done["payload"]["task"]["status"], "done")
            self.assertTrue(removed["ok"])
            self.assertTrue(removed["payload"]["removed"])

    def test_task_action_errors_are_enveloped(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            state = HelperState(base_dir=Path(tmp))

            bad_payload = handle_request(
                {
                    "version": 1,
                    "id": "bad-action",
                    "command": "task.markDone",
                    "payload": {"id": 0},
                },
                state,
            )
            missing = handle_request(
                {
                    "version": 1,
                    "id": "missing-action",
                    "command": "task.markDone",
                    "payload": {"id": 99},
                },
                state,
            )

            self.assertFalse(bad_payload["ok"])
            self.assertEqual(bad_payload["error"]["code"], "payload.invalid")
            self.assertFalse(missing["ok"])
            self.assertEqual(missing["error"]["code"], "task.notFound")

    def test_task_action_uses_selected_workspace_database(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            base_db = root / "agendum.db"
            namespace_db = root / "workspaces" / "example-org" / "agendum.db"
            init_db(base_db)
            init_db(namespace_db)
            add_task(
                base_db,
                title="Base task",
                source="manual",
                status="backlog",
            )
            namespace_id = add_task(
                namespace_db,
                title="Namespaced task",
                source="manual",
                status="backlog",
            )

            response = handle_request(
                {
                    "version": 1,
                    "id": "namespace-action",
                    "command": "task.markDone",
                    "payload": {"id": namespace_id},
                },
                HelperState(base_dir=root, namespace="example-org"),
            )

            self.assertTrue(response["ok"])
            self.assertEqual(response["payload"]["task"]["title"], "Namespaced task")
            self.assertEqual(response["payload"]["task"]["status"], "done")

    def test_sync_status_and_force_sync(self) -> None:
        async def fake_run_sync(db_path, config):
            self.assertEqual(db_path, root / "agendum.db")
            self.assertEqual(config.orgs, [])
            await asyncio.sleep(0.05)
            return 3, True, None

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            state = HelperState(base_dir=root)

            initial = handle_request(
                {
                    "version": 1,
                    "id": "sync-status-before",
                    "command": "sync.status",
                    "payload": {},
                },
                state,
            )
            with mock.patch("Backend.agendum_backend.helper.run_sync", side_effect=fake_run_sync):
                forced = handle_request(
                    {
                        "version": 1,
                        "id": "sync-force",
                        "command": "sync.force",
                        "payload": {},
                    },
                    state,
                )
            after = handle_request(
                {
                    "version": 1,
                    "id": "sync-status-after",
                    "command": "sync.status",
                    "payload": {},
                },
                state,
            )

            self.assertTrue(initial["ok"])
            self.assertEqual(initial["payload"]["status"]["state"], "idle")
            self.assertTrue(forced["ok"])
            self.assertEqual(forced["payload"]["status"]["state"], "running")
            self.assertEqual(after["payload"]["status"]["state"], "running")
            completed = wait_for_sync_state(state, "idle")
            self.assertEqual(completed["changes"], 3)
            self.assertTrue(completed["hasAttentionItems"])
            self.assertIsNotNone(completed["lastSyncAt"])

    def test_force_sync_returns_running_when_sync_is_already_running(self) -> None:
        async def fake_run_sync(db_path, config):
            await asyncio.sleep(0.1)
            return 1, False, None

        with tempfile.TemporaryDirectory() as tmp:
            state = HelperState(base_dir=Path(tmp))

            with mock.patch("Backend.agendum_backend.helper.run_sync", side_effect=fake_run_sync):
                first = handle_request(
                    {
                        "version": 1,
                        "id": "sync-force-first",
                        "command": "sync.force",
                        "payload": {},
                    },
                    state,
                )
                second = handle_request(
                    {
                        "version": 1,
                        "id": "sync-force-second",
                        "command": "sync.force",
                        "payload": {},
                    },
                    state,
                )

            self.assertTrue(first["ok"])
            self.assertTrue(second["ok"])
            self.assertEqual(first["payload"]["status"]["state"], "running")
            self.assertEqual(second["payload"]["status"]["state"], "running")
            completed = wait_for_sync_state(state, "idle")
            self.assertEqual(completed["changes"], 1)

    def test_force_sync_reports_error_status(self) -> None:
        async def fake_run_sync(db_path, config):
            return 0, False, "gh credentials expired"

        with tempfile.TemporaryDirectory() as tmp:
            state = HelperState(base_dir=Path(tmp))

            with mock.patch("Backend.agendum_backend.helper.run_sync", side_effect=fake_run_sync):
                response = handle_request(
                    {
                        "version": 1,
                        "id": "sync-force-error",
                        "command": "sync.force",
                        "payload": {},
                    },
                    state,
                )

            self.assertTrue(response["ok"])
            self.assertEqual(response["payload"]["status"]["state"], "running")
            completed = wait_for_sync_state(state, "error")
            self.assertEqual(completed["lastError"], "gh credentials expired")

    def test_force_sync_reports_exception_status_and_helper_continues(self) -> None:
        async def fake_run_sync(db_path, config):
            raise RuntimeError("sync transport failed")

        with tempfile.TemporaryDirectory() as tmp:
            state = HelperState(base_dir=Path(tmp))

            with mock.patch("Backend.agendum_backend.helper.run_sync", side_effect=fake_run_sync):
                response = handle_request(
                    {
                        "version": 1,
                        "id": "sync-force-exception",
                        "command": "sync.force",
                        "payload": {},
                    },
                    state,
                )

            self.assertTrue(response["ok"])
            self.assertEqual(response["payload"]["status"]["state"], "running")
            completed = wait_for_sync_state(state, "error")
            self.assertEqual(completed["lastError"], "sync transport failed")
            status = handle_request(
                {
                    "version": 1,
                    "id": "sync-status-after-exception",
                    "command": "sync.status",
                    "payload": {},
                },
                state,
            )
            self.assertEqual(status["payload"]["status"], completed)

    def test_workspace_select_resets_sync_status(self) -> None:
        async def fake_run_sync(db_path, config):
            return 0, False, "gh credentials expired"

        with tempfile.TemporaryDirectory() as tmp:
            state = HelperState(base_dir=Path(tmp))

            with mock.patch("Backend.agendum_backend.helper.run_sync", side_effect=fake_run_sync):
                handle_request(
                    {
                        "version": 1,
                        "id": "sync-force-before-select",
                        "command": "sync.force",
                        "payload": {},
                    },
                    state,
                )
            wait_for_sync_state(state, "error")
            selection = handle_request(
                {
                    "version": 1,
                    "id": "select-after-sync-error",
                    "command": "workspace.select",
                    "payload": {"namespace": "Example-Org"},
                },
                state,
            )
            status = handle_request(
                {
                    "version": 1,
                    "id": "status-after-select",
                    "command": "sync.status",
                    "payload": {},
                },
                state,
            )

            self.assertTrue(selection["ok"])
            self.assertEqual(selection["payload"]["sync"]["state"], "idle")
            self.assertIsNone(selection["payload"]["sync"]["lastError"])
            self.assertEqual(status["payload"]["status"], selection["payload"]["sync"])

    def test_auth_status_reports_missing_gh(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            state = HelperState(base_dir=Path(tmp))
            with mock.patch("Backend.agendum_backend.helper._find_gh", return_value=None):
                response = handle_request(
                    {
                        "version": 1,
                        "id": "req-2",
                        "command": "auth.status",
                        "payload": {},
                    },
                    state,
                )

            auth = response["payload"]["auth"]
            self.assertTrue(response["ok"])
            self.assertFalse(auth["ghFound"])
            self.assertFalse(auth["authenticated"])
            self.assertIsNotNone(auth["repairInstructions"])

    def test_auth_status_uses_configured_gh_path_and_workspace_config_dir(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            fake_gh = root / "gh"
            fake_gh.write_text(
                "#!/bin/sh\n"
                "if [ \"$1 $2\" = \"auth status\" ]; then exit 0; fi\n"
                "if [ \"$1 $2 $3 $4\" = \"api user --jq .login\" ]; then echo dan; exit 0; fi\n"
                "exit 1\n"
            )
            fake_gh.chmod(fake_gh.stat().st_mode | stat.S_IXUSR)

            state = HelperState(base_dir=root / "agendum")
            with mock.patch.dict(
                os.environ,
                {"AGENDUM_MAC_GH_PATHS": str(fake_gh), "PATH": ""},
                clear=False,
            ):
                response = handle_request(
                    {
                        "version": 1,
                        "id": "req-3",
                        "command": "auth.status",
                        "payload": {},
                    },
                    state,
                )

            auth = response["payload"]["auth"]
            self.assertTrue(response["ok"])
            self.assertTrue(auth["ghFound"])
            self.assertEqual(auth["ghPath"], str(fake_gh))
            self.assertTrue(auth["authenticated"])
            self.assertEqual(auth["username"], "dan")
            self.assertEqual(auth["workspaceGhConfigDir"], str(root / "agendum" / "gh"))

    def test_auth_status_reports_unauthenticated_gh(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            fake_gh = root / "gh"
            fake_gh.write_text("#!/bin/sh\nexit 1\n")
            fake_gh.chmod(fake_gh.stat().st_mode | stat.S_IXUSR)

            state = HelperState(base_dir=root / "agendum")
            with mock.patch("Backend.agendum_backend.helper._find_gh", return_value=fake_gh):
                response = handle_request(
                    {
                        "version": 1,
                        "id": "req-auth-missing",
                        "command": "auth.status",
                        "payload": {},
                    },
                    state,
                )

            auth = response["payload"]["auth"]
            self.assertTrue(response["ok"])
            self.assertTrue(auth["ghFound"])
            self.assertEqual(auth["ghPath"], str(fake_gh))
            self.assertFalse(auth["authenticated"])
            self.assertIsNone(auth["username"])
            self.assertIn("gh auth login", auth["repairInstructions"])

    def test_auth_status_allows_authenticated_gh_without_username(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            fake_gh = root / "gh"
            fake_gh.write_text(
                "#!/bin/sh\n"
                "if [ \"$1 $2\" = \"auth status\" ]; then exit 0; fi\n"
                "exit 1\n"
            )
            fake_gh.chmod(fake_gh.stat().st_mode | stat.S_IXUSR)

            state = HelperState(base_dir=root / "agendum")
            with mock.patch("Backend.agendum_backend.helper._find_gh", return_value=fake_gh):
                response = handle_request(
                    {
                        "version": 1,
                        "id": "req-auth-username-missing",
                        "command": "auth.status",
                        "payload": {},
                    },
                    state,
                )

            auth = response["payload"]["auth"]
            self.assertTrue(response["ok"])
            self.assertTrue(auth["authenticated"])
            self.assertIsNone(auth["username"])

    def test_auth_diagnose_returns_full_payload_when_gh_authenticated(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            fake_gh = root / "gh"
            fake_gh.write_text(
                "#!/bin/sh\n"
                "if [ \"$1\" = \"--version\" ]; then echo 'gh version 2.50.0 (2024-04-01)'; exit 0; fi\n"
                "if [ \"$1 $2\" = \"auth status\" ]; then exit 0; fi\n"
                "if [ \"$1 $2 $3 $4\" = \"api user --jq .login\" ]; then echo dan; exit 0; fi\n"
                "exit 1\n"
            )
            fake_gh.chmod(fake_gh.stat().st_mode | stat.S_IXUSR)

            state = HelperState(base_dir=root / "agendum")
            with mock.patch.dict(
                os.environ,
                {
                    "AGENDUM_MAC_GH_PATHS": str(fake_gh),
                    "PATH": "/usr/bin:/bin",
                    "GH_HOST": "github.com",
                },
                clear=False,
            ):
                response = handle_request(
                    {
                        "version": 1,
                        "id": "diagnose-ok",
                        "command": "auth.diagnose",
                        "payload": {},
                    },
                    state,
                )

            self.assertTrue(response["ok"])
            diagnostics = response["payload"]["diagnostics"]
            self.assertTrue(diagnostics["gh"]["found"])
            self.assertTrue(diagnostics["gh"]["installed"])
            self.assertEqual(diagnostics["gh"]["path"], str(fake_gh))
            self.assertEqual(diagnostics["gh"]["version"], "gh version 2.50.0 (2024-04-01)")
            self.assertTrue(diagnostics["auth"]["authenticated"])
            self.assertEqual(diagnostics["host"], "github.com")
            self.assertEqual(diagnostics["helperPath"], ["/usr/bin", "/bin"])

    def test_auth_diagnose_when_gh_missing_reports_not_found(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            state = HelperState(base_dir=Path(tmp))
            with mock.patch.dict(
                os.environ,
                {"AGENDUM_MAC_GH_PATHS": "", "PATH": "/usr/bin"},
                clear=False,
            ):
                with mock.patch(
                    "Backend.agendum_backend.helper._find_gh", return_value=None
                ):
                    response = handle_request(
                        {
                            "version": 1,
                            "id": "diagnose-missing",
                            "command": "auth.diagnose",
                            "payload": {},
                        },
                        state,
                    )

            diagnostics = response["payload"]["diagnostics"]
            self.assertTrue(response["ok"])
            self.assertFalse(diagnostics["gh"]["found"])
            self.assertIsNone(diagnostics["gh"]["path"])
            self.assertIsNone(diagnostics["gh"]["version"])
            self.assertFalse(diagnostics["auth"]["ghFound"])
            self.assertIsNone(diagnostics["auth"]["repairCommand"])
            self.assertEqual(diagnostics["helperPath"], ["/usr/bin"])

    def test_auth_diagnose_when_gh_installed_but_not_authenticated(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            fake_gh = root / "gh"
            fake_gh.write_text(
                "#!/bin/sh\n"
                "if [ \"$1\" = \"--version\" ]; then echo 'gh version 2.50.0'; exit 0; fi\n"
                "exit 1\n"
            )
            fake_gh.chmod(fake_gh.stat().st_mode | stat.S_IXUSR)

            state = HelperState(base_dir=root / "agendum")
            with mock.patch("Backend.agendum_backend.helper._find_gh", return_value=fake_gh):
                response = handle_request(
                    {
                        "version": 1,
                        "id": "diagnose-unauth",
                        "command": "auth.diagnose",
                        "payload": {},
                    },
                    state,
                )

            diagnostics = response["payload"]["diagnostics"]
            self.assertTrue(response["ok"])
            self.assertTrue(diagnostics["gh"]["found"])
            self.assertEqual(diagnostics["gh"]["version"], "gh version 2.50.0")
            self.assertFalse(diagnostics["auth"]["authenticated"])
            expected_command = _format_repair_command((root / "agendum" / "gh"))
            self.assertEqual(diagnostics["auth"]["repairCommand"], expected_command)

            # Now verify gh-missing branch: repairCommand is None
            with mock.patch("Backend.agendum_backend.helper._find_gh", return_value=None):
                response_missing = handle_request(
                    {
                        "version": 1,
                        "id": "diagnose-unauth-missing",
                        "command": "auth.diagnose",
                        "payload": {},
                    },
                    HelperState(base_dir=root / "agendum2"),
                )
            self.assertIsNone(response_missing["payload"]["diagnostics"]["auth"]["repairCommand"])

    def test_auth_diagnose_helper_path_filters_empty_entries(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            state = HelperState(base_dir=Path(tmp))
            with mock.patch.dict(
                os.environ,
                {"AGENDUM_MAC_GH_PATHS": "", "PATH": "/a::/b:"},
                clear=False,
            ):
                with mock.patch(
                    "Backend.agendum_backend.helper._find_gh", return_value=None
                ):
                    response = handle_request(
                        {
                            "version": 1,
                            "id": "diagnose-path",
                            "command": "auth.diagnose",
                            "payload": {},
                        },
                        state,
                    )

            self.assertEqual(response["payload"]["diagnostics"]["helperPath"], ["/a", "/b"])

    def test_auth_diagnose_host_uses_gh_host_env(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            state = HelperState(base_dir=Path(tmp))
            with mock.patch.dict(
                os.environ,
                {"AGENDUM_MAC_GH_PATHS": "", "GH_HOST": "ghe.example.com"},
                clear=False,
            ):
                with mock.patch(
                    "Backend.agendum_backend.helper._find_gh", return_value=None
                ):
                    response = handle_request(
                        {
                            "version": 1,
                            "id": "diagnose-host",
                            "command": "auth.diagnose",
                            "payload": {},
                        },
                        state,
                    )

            self.assertEqual(response["payload"]["diagnostics"]["host"], "ghe.example.com")

    def test_auth_diagnose_host_defaults_to_github_com(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            state = HelperState(base_dir=Path(tmp))
            env = {k: v for k, v in os.environ.items() if k != "GH_HOST"}
            env["AGENDUM_MAC_GH_PATHS"] = ""
            with mock.patch.dict(os.environ, env, clear=True):
                with mock.patch(
                    "Backend.agendum_backend.helper._find_gh", return_value=None
                ):
                    response = handle_request(
                        {
                            "version": 1,
                            "id": "diagnose-host-default",
                            "command": "auth.diagnose",
                            "payload": {},
                        },
                        state,
                    )

            self.assertEqual(response["payload"]["diagnostics"]["host"], "github.com")

    def test_auth_diagnose_gh_version_returns_first_line(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            fake_gh = root / "gh"
            fake_gh.write_text(
                "#!/bin/sh\n"
                "if [ \"$1\" = \"--version\" ]; then\n"
                "  printf 'gh version 2.50.0 (2024-04-01)\\nhttps://example/cli/releases/v2.50.0\\n'\n"
                "  exit 0\n"
                "fi\n"
                "exit 1\n"
            )
            fake_gh.chmod(fake_gh.stat().st_mode | stat.S_IXUSR)

            self.assertEqual(_gh_version(fake_gh), "gh version 2.50.0 (2024-04-01)")

    def test_auth_diagnose_gh_version_returns_none_when_command_fails(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            fake_gh = root / "gh"
            fake_gh.write_text("#!/bin/sh\nexit 1\n")
            fake_gh.chmod(fake_gh.stat().st_mode | stat.S_IXUSR)

            self.assertIsNone(_gh_version(fake_gh))

    def test_auth_diagnose_maps_storage_failure_when_workspace_config_raises(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            state = HelperState(base_dir=Path(tmp))
            with mock.patch(
                "Backend.agendum_backend.helper.ensure_workspace_config",
                side_effect=OSError("disk denied"),
            ):
                response = handle_request(
                    {
                        "version": 1,
                        "id": "diagnose-storage-fail",
                        "command": "auth.diagnose",
                        "payload": {},
                    },
                    state,
                )

            self.assertFalse(response["ok"])
            self.assertEqual(response["error"]["code"], "storage.failed")

    def test_format_repair_command_quotes_paths_with_spaces(self) -> None:
        with_spaces = _format_repair_command(Path("/Users/x/My Stuff/.agendum/gh"))
        self.assertIn("'/Users/x/My Stuff/.agendum/gh'", with_spaces)

        plain = _format_repair_command(Path("/Users/x/.agendum/gh"))
        self.assertEqual(plain, "GH_CONFIG_DIR=/Users/x/.agendum/gh gh auth login")

    def test_auth_status_repair_command_uses_shared_formatter(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            fake_gh = root / "gh"
            fake_gh.write_text("#!/bin/sh\nexit 1\n")
            fake_gh.chmod(fake_gh.stat().st_mode | stat.S_IXUSR)

            base_dir = root / "My Stuff" / "agendum"
            state = HelperState(base_dir=base_dir)
            with mock.patch("Backend.agendum_backend.helper._find_gh", return_value=fake_gh):
                auth = auth_status(state)

            expected = _format_repair_command(base_dir / "gh")
            self.assertEqual(auth["repairCommand"], expected)
            self.assertIn(expected, auth["repairInstructions"])

    def test_gh_version_returns_none_for_empty_stdout_on_exit_zero(self) -> None:
        completed = subprocess.CompletedProcess(args=["gh", "--version"], returncode=0, stdout="", stderr="")
        with mock.patch("Backend.agendum_backend.helper.subprocess.run", return_value=completed):
            self.assertIsNone(_gh_version(Path("/usr/bin/gh")))

    def test_protocol_errors_are_enveloped(self) -> None:
        response = handle_request(
            {"version": 999, "id": "bad", "command": "workspace.current", "payload": {}},
            HelperState(base_dir=Path("/tmp/agendum-test")),
        )

        self.assertFalse(response["ok"])
        self.assertEqual(response["error"]["code"], "protocol.unsupportedVersion")

    def test_workspace_value_error_is_enveloped(self) -> None:
        with mock.patch(
            "Backend.agendum_backend.helper.current_workspace",
            side_effect=ValueError("bad namespace"),
        ):
            response = handle_request(
                {
                    "version": 1,
                    "id": "bad-workspace",
                    "command": "workspace.current",
                    "payload": {},
                },
                HelperState(base_dir=Path("/tmp/agendum-test")),
            )

        self.assertFalse(response["ok"])
        self.assertEqual(response["id"], "bad-workspace")
        self.assertEqual(response["error"]["code"], "workspace.invalid")
        self.assertEqual(response["error"]["detail"], "bad namespace")

    def test_workspace_os_error_is_enveloped(self) -> None:
        with mock.patch(
            "Backend.agendum_backend.helper.current_workspace",
            side_effect=OSError("disk denied"),
        ):
            response = handle_request(
                {
                    "version": 1,
                    "id": "storage-error",
                    "command": "workspace.current",
                    "payload": {},
                },
                HelperState(base_dir=Path("/tmp/agendum-test")),
            )

        self.assertFalse(response["ok"])
        self.assertEqual(response["id"], "storage-error")
        self.assertEqual(response["error"]["code"], "storage.failed")
        self.assertEqual(response["error"]["detail"], "disk denied")

    def test_invalid_json_is_enveloped(self) -> None:
        response = handle_line("{", HelperState(base_dir=Path("/tmp/agendum-test")))

        self.assertFalse(response["ok"])
        self.assertEqual(response["id"], None)
        self.assertEqual(response["error"]["code"], "payload.invalid")
        self.assertEqual(response["error"]["message"], "Request is not valid JSON.")

    def test_non_object_json_request_is_enveloped(self) -> None:
        response = handle_line("[]", HelperState(base_dir=Path("/tmp/agendum-test")))

        self.assertFalse(response["ok"])
        self.assertEqual(response["error"]["code"], "payload.invalid")
        self.assertEqual(response["error"]["message"], "Request envelope must be an object.")

    def test_non_object_payload_is_enveloped(self) -> None:
        response = handle_request(
            {
                "version": 1,
                "id": "bad-payload",
                "command": "workspace.current",
                "payload": [],
            },
            HelperState(base_dir=Path("/tmp/agendum-test")),
        )

        self.assertFalse(response["ok"])
        self.assertEqual(response["id"], "bad-payload")
        self.assertEqual(response["error"]["code"], "payload.invalid")
        self.assertEqual(response["error"]["message"], "Request payload must be an object.")

    def test_missing_payload_defaults_to_empty_object(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            response = handle_request(
                {
                    "version": 1,
                    "id": "req-no-payload",
                    "command": "workspace.current",
                },
                HelperState(base_dir=Path(tmp)),
            )

            self.assertTrue(response["ok"])
            self.assertEqual(response["id"], "req-no-payload")
            self.assertEqual(response["payload"]["workspace"]["id"], "base")

    def test_unknown_command_is_enveloped(self) -> None:
        response = handle_request(
            {
                "version": 1,
                "id": "unknown",
                "command": "unknown.command",
                "payload": {},
            },
            HelperState(base_dir=Path("/tmp/agendum-test")),
        )

        self.assertFalse(response["ok"])
        self.assertEqual(response["id"], "unknown")
        self.assertEqual(response["error"]["code"], "protocol.unknownCommand")
        self.assertEqual(response["error"]["detail"], "unknown.command")


if __name__ == "__main__":
    unittest.main()
