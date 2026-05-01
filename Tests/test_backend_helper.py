from __future__ import annotations

import json
import os
import stat
import tempfile
import unittest
from io import StringIO
from pathlib import Path
from unittest import mock

from Backend.agendum_backend.helper import HelperState, handle_line, handle_request, run_stdio
from agendum.db import add_task, init_db, update_task


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
        state = HelperState(base_dir=Path("/tmp/agendum-test"))

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
