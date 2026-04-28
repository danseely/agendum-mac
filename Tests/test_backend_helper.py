from __future__ import annotations

import json
import os
import stat
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from Backend.agendum_backend.helper import HelperState, handle_line, handle_request


class BackendHelperTests(unittest.TestCase):
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

    def test_protocol_errors_are_enveloped(self) -> None:
        response = handle_request(
            {"version": 999, "id": "bad", "command": "workspace.current", "payload": {}},
            HelperState(base_dir=Path("/tmp/agendum-test")),
        )

        self.assertFalse(response["ok"])
        self.assertEqual(response["error"]["code"], "protocol.unsupportedVersion")

    def test_non_object_json_request_is_enveloped(self) -> None:
        response = handle_line("[]", HelperState(base_dir=Path("/tmp/agendum-test")))

        self.assertFalse(response["ok"])
        self.assertEqual(response["error"]["code"], "payload.invalid")
        self.assertEqual(response["error"]["message"], "Request envelope must be an object.")


if __name__ == "__main__":
    unittest.main()
