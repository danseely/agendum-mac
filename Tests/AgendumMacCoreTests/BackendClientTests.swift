@testable import AgendumMacCore
import Foundation
import XCTest

final class BackendClientTests: XCTestCase {
    func testClientUsesOneHelperProcessForWorkspaceAndAuthRequests() async throws {
        let root = temporaryDirectory()
        let baseDir = root.appendingPathComponent("agendum")
        let fakeGH = root.appendingPathComponent("gh")
        let expectedConfigDir = baseDir.appendingPathComponent("gh")

        try writeExecutable(
            at: fakeGH,
            contents: """
            #!/bin/sh
            if [ "$GH_CONFIG_DIR" != "\(expectedConfigDir.path)" ]; then exit 2; fi
            if [ "$1 $2" = "auth status" ]; then exit 0; fi
            if [ "$1 $2 $3 $4" = "api user --jq .login" ]; then echo dan; exit 0; fi
            exit 1
            """
        )

        let client = AgendumBackendClient(
            configuration: BackendClientConfiguration(
                helperURL: repositoryRoot().appendingPathComponent("Backend/agendum_backend_helper.py"),
                workingDirectoryURL: repositoryRoot(),
                environment: [
                    "AGENDUM_MAC_BASE_DIR": baseDir.path,
                    "AGENDUM_MAC_GH_PATHS": fakeGH.path,
                    "PATH": "",
                ]
            )
        )

        let workspace = try await client.currentWorkspace()
        let auth = try await client.authStatus()
        await client.close()

        XCTAssertEqual(workspace.id, "base")
        XCTAssertNil(workspace.namespace)
        XCTAssertEqual(workspace.configPath, baseDir.appendingPathComponent("config.toml").path)
        XCTAssertEqual(workspace.dbPath, baseDir.appendingPathComponent("agendum.db").path)
        XCTAssertTrue(workspace.isCurrent)

        XCTAssertTrue(auth.ghFound)
        XCTAssertEqual(auth.ghPath, fakeGH.path)
        XCTAssertTrue(auth.authenticated)
        XCTAssertEqual(auth.username, "dan")
        XCTAssertEqual(auth.workspaceGhConfigDir, expectedConfigDir.path)
    }

    func testClientListsAndSelectsWorkspacesInOneHelperProcess() async throws {
        let root = temporaryDirectory()
        let baseDir = root.appendingPathComponent("agendum")
        let fakeGH = root.appendingPathComponent("gh")

        try writeExecutable(
            at: fakeGH,
            contents: """
            #!/bin/sh
            if [ "$1 $2" = "auth status" ]; then exit 0; fi
            if [ "$1 $2 $3 $4" = "api user --jq .login" ]; then echo dan; exit 0; fi
            exit 1
            """
        )

        let client = AgendumBackendClient(
            configuration: BackendClientConfiguration(
                helperURL: repositoryRoot().appendingPathComponent("Backend/agendum_backend_helper.py"),
                workingDirectoryURL: repositoryRoot(),
                environment: [
                    "AGENDUM_MAC_BASE_DIR": baseDir.path,
                    "AGENDUM_MAC_GH_PATHS": fakeGH.path,
                    "PATH": "",
                ]
            )
        )

        let selection = try await client.selectWorkspace(namespace: "Example-Org")
        let current = try await client.currentWorkspace()
        let workspaces = try await client.listWorkspaces()
        let baseSelection = try await client.selectWorkspace(namespace: nil)
        await client.close()

        XCTAssertEqual(selection.workspace.id, "example-org")
        XCTAssertEqual(selection.workspace.namespace, "example-org")
        XCTAssertEqual(selection.auth.workspaceGhConfigDir, baseDir.appendingPathComponent("workspaces/example-org/gh").path)
        XCTAssertEqual(selection.sync.state, "idle")
        XCTAssertEqual(selection.sync.changes, 0)
        XCTAssertEqual(current.id, "example-org")
        XCTAssertEqual(workspaces.map(\.id), ["base", "example-org"])
        XCTAssertFalse(workspaces[0].isCurrent)
        XCTAssertTrue(workspaces[1].isCurrent)
        XCTAssertEqual(baseSelection.workspace.id, "base")
        XCTAssertNil(baseSelection.workspace.namespace)
    }

    func testClientListsTasks() async throws {
        let helper = try writePythonHelper(
            contents: """
            import json
            import sys

            for line in sys.stdin:
                request = json.loads(line)
                payload = request["payload"]
                if (
                    request["command"] != "task.list"
                    or payload["source"] != "pr_review"
                    or payload["status"] != "review requested"
                    or payload["project"] != "homebrew-tap"
                    or payload["includeSeen"] != False
                    or payload["limit"] != 5
                ):
                    print(json.dumps({
                        "version": 1,
                        "id": request["id"],
                        "ok": False,
                        "error": {"code": "test.failed", "message": "unexpected task.list request"}
                    }), flush=True)
                    continue
                print(json.dumps({
                    "version": 1,
                    "id": request["id"],
                    "ok": True,
                    "payload": {"tasks": [{
                        "id": 17,
                        "title": "Review release workflow hardening",
                        "source": "pr_review",
                        "status": "review requested",
                        "project": "homebrew-tap",
                        "ghRepo": "danseely/homebrew-tap",
                        "ghUrl": "https://github.com/danseely/homebrew-tap/pull/17",
                        "ghNumber": 17,
                        "ghAuthor": "octocat",
                        "ghAuthorName": "Octo",
                        "tags": ["review"],
                        "seen": False,
                        "lastChangedAt": "2026-04-28T15:00:00+00:00",
                        "updatedAt": "2026-04-28T15:01:00+00:00"
                    }]}
                }), flush=True)
            """
        )
        let client = AgendumBackendClient(configuration: fakeHelperConfiguration(helperURL: helper))

        let tasks = try await client.listTasks(
            source: "pr_review",
            status: "review requested",
            project: "homebrew-tap",
            includeSeen: false,
            limit: 5
        )
        await client.close()

        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks[0].id, 17)
        XCTAssertEqual(tasks[0].title, "Review release workflow hardening")
        XCTAssertEqual(tasks[0].source, "pr_review")
        XCTAssertEqual(tasks[0].status, "review requested")
        XCTAssertEqual(tasks[0].project, "homebrew-tap")
        XCTAssertEqual(tasks[0].ghRepo, "danseely/homebrew-tap")
        XCTAssertEqual(tasks[0].ghUrl, "https://github.com/danseely/homebrew-tap/pull/17")
        XCTAssertEqual(tasks[0].ghNumber, 17)
        XCTAssertEqual(tasks[0].ghAuthor, "octocat")
        XCTAssertEqual(tasks[0].ghAuthorName, "Octo")
        XCTAssertEqual(tasks[0].tags, ["review"])
        XCTAssertFalse(tasks[0].seen)
        XCTAssertEqual(tasks[0].lastChangedAt, "2026-04-28T15:00:00+00:00")
        XCTAssertEqual(tasks[0].updatedAt, "2026-04-28T15:01:00+00:00")
    }

    func testClientHandlesTaskActionsAndSync() async throws {
        let helper = try writePythonHelper(
            contents: """
            import json
            import sys

            expected = [
                ("task.get", 17),
                ("task.markReviewed", 17),
                ("task.markInProgress", 18),
                ("task.moveToBacklog", 18),
                ("task.markSeen", 18),
                ("task.markDone", 18),
                ("task.remove", 18),
                ("sync.status", None),
                ("sync.force", None),
            ]

            def task_payload(task_id, status, seen=False):
                return {
                    "id": task_id,
                    "title": "Task " + str(task_id),
                    "source": "manual",
                    "status": status,
                    "project": "agendum-mac",
                    "ghRepo": None,
                    "ghUrl": None,
                    "ghNumber": None,
                    "ghAuthor": None,
                    "ghAuthorName": None,
                    "tags": [],
                    "seen": seen,
                    "lastChangedAt": "2026-04-28T15:00:00+00:00",
                    "updatedAt": "2026-04-28T15:01:00+00:00",
                }

            for index, line in enumerate(sys.stdin):
                request = json.loads(line)
                command, expected_id = expected[index]
                payload = request["payload"]
                if request["command"] != command or (expected_id is not None and payload["id"] != expected_id):
                    print(json.dumps({
                        "version": 1,
                        "id": request["id"],
                        "ok": False,
                        "error": {"code": "test.failed", "message": "unexpected request"}
                    }), flush=True)
                    continue

                if command == "task.get":
                    response_payload = {"task": task_payload(17, "review requested")}
                elif command == "task.markReviewed":
                    response_payload = {"task": task_payload(17, "reviewed")}
                elif command == "task.markInProgress":
                    response_payload = {"task": task_payload(18, "in progress")}
                elif command == "task.moveToBacklog":
                    response_payload = {"task": task_payload(18, "backlog")}
                elif command == "task.markSeen":
                    response_payload = {"task": task_payload(18, "backlog", seen=True)}
                elif command == "task.markDone":
                    response_payload = {"task": task_payload(18, "done", seen=True)}
                elif command == "task.remove":
                    response_payload = {"removed": True}
                elif command == "sync.status":
                    response_payload = {"status": {
                        "state": "idle",
                        "lastSyncAt": None,
                        "lastError": None,
                        "changes": 0,
                        "hasAttentionItems": False
                    }}
                else:
                    response_payload = {"status": {
                        "state": "idle",
                        "lastSyncAt": "2026-05-01T20:00:00+00:00",
                        "lastError": None,
                        "changes": 2,
                        "hasAttentionItems": True
                    }}

                print(json.dumps({
                    "version": 1,
                    "id": request["id"],
                    "ok": True,
                    "payload": response_payload
                }), flush=True)
            """
        )
        let client = AgendumBackendClient(configuration: fakeHelperConfiguration(helperURL: helper))

        let loaded = try await client.getTask(id: 17)
        let reviewed = try await client.markTaskReviewed(id: 17)
        let inProgress = try await client.markTaskInProgress(id: 18)
        let backlog = try await client.moveTaskToBacklog(id: 18)
        let seen = try await client.markTaskSeen(id: 18)
        let done = try await client.markTaskDone(id: 18)
        let removed = try await client.removeTask(id: 18)
        let syncBefore = try await client.syncStatus()
        let syncAfter = try await client.forceSync()
        await client.close()

        XCTAssertEqual(loaded?.id, 17)
        XCTAssertEqual(reviewed.status, "reviewed")
        XCTAssertEqual(inProgress.status, "in progress")
        XCTAssertEqual(backlog.status, "backlog")
        XCTAssertTrue(seen.seen)
        XCTAssertEqual(done.status, "done")
        XCTAssertTrue(removed)
        XCTAssertEqual(syncBefore.state, "idle")
        XCTAssertEqual(syncBefore.changes, 0)
        XCTAssertEqual(syncAfter.changes, 2)
        XCTAssertTrue(syncAfter.hasAttentionItems)
        XCTAssertEqual(syncAfter.lastSyncAt, "2026-05-01T20:00:00+00:00")
    }

    func testClientCreatesManualTask() async throws {
        let helper = try writePythonHelper(
            contents: """
            import json
            import sys

            expected = [
                {
                    "title": "Sketch Mac backend contract",
                    "project": "agendum-mac",
                    "tags": ["planning", "design"],
                },
                {"title": "Minimal task"},
            ]
            responses = [
                {
                    "id": 42,
                    "title": "Sketch Mac backend contract",
                    "source": "manual",
                    "status": "backlog",
                    "project": "agendum-mac",
                    "ghRepo": None,
                    "ghUrl": None,
                    "ghNumber": None,
                    "ghAuthor": None,
                    "ghAuthorName": None,
                    "tags": ["planning", "design"],
                    "seen": True,
                    "lastChangedAt": "2026-05-02T15:00:00+00:00",
                    "updatedAt": "2026-05-02T15:01:00+00:00",
                },
                {
                    "id": 43,
                    "title": "Minimal task",
                    "source": "manual",
                    "status": "backlog",
                    "project": None,
                    "ghRepo": None,
                    "ghUrl": None,
                    "ghNumber": None,
                    "ghAuthor": None,
                    "ghAuthorName": None,
                    "tags": [],
                    "seen": True,
                    "lastChangedAt": "2026-05-02T15:02:00+00:00",
                    "updatedAt": "2026-05-02T15:02:00+00:00",
                },
            ]

            for index, line in enumerate(sys.stdin):
                request = json.loads(line)
                payload = request["payload"]
                expected_payload = expected[index]
                if (
                    request["command"] != "task.createManual"
                    or payload != expected_payload
                ):
                    print(json.dumps({
                        "version": 1,
                        "id": request["id"],
                        "ok": False,
                        "error": {
                            "code": "test.failed",
                            "message": "unexpected createManual request",
                            "detail": json.dumps(payload),
                        }
                    }), flush=True)
                    continue
                print(json.dumps({
                    "version": 1,
                    "id": request["id"],
                    "ok": True,
                    "payload": {"task": responses[index]},
                }), flush=True)
            """
        )
        let client = AgendumBackendClient(configuration: fakeHelperConfiguration(helperURL: helper))

        let created = try await client.createManualTask(
            title: "Sketch Mac backend contract",
            project: "agendum-mac",
            tags: ["planning", "design"]
        )
        let minimal = try await client.createManualTask(title: "Minimal task")
        await client.close()

        XCTAssertEqual(created.id, 42)
        XCTAssertEqual(created.title, "Sketch Mac backend contract")
        XCTAssertEqual(created.source, "manual")
        XCTAssertEqual(created.status, "backlog")
        XCTAssertEqual(created.project, "agendum-mac")
        XCTAssertEqual(created.tags, ["planning", "design"])

        XCTAssertEqual(minimal.id, 43)
        XCTAssertEqual(minimal.title, "Minimal task")
        XCTAssertNil(minimal.project)
        XCTAssertEqual(minimal.tags, [])
    }

    func testClientReusesOneHelperProcess() async throws {
        let helper = try writePythonHelper(
            contents: """
            import json
            import os
            import sys

            for line in sys.stdin:
                request = json.loads(line)
                print(json.dumps({
                    "version": 1,
                    "id": request["id"],
                    "ok": True,
                    "payload": {"processID": os.getpid()}
                }), flush=True)
            """
        )
        let client = AgendumBackendClient(configuration: fakeHelperConfiguration(helperURL: helper))

        let first = try await client.request(command: "first", as: ProcessIDPayload.self)
        let second = try await client.request(command: "second", as: ProcessIDPayload.self)
        await client.close()

        XCTAssertEqual(first.processID, second.processID)
    }

    func testClientMapsBackendErrors() async throws {
        let client = AgendumBackendClient(
            configuration: BackendClientConfiguration(
                helperURL: repositoryRoot().appendingPathComponent("Backend/agendum_backend_helper.py"),
                workingDirectoryURL: repositoryRoot(),
                environment: [
                    "AGENDUM_MAC_BASE_DIR": temporaryDirectory().path,
                    "AGENDUM_MAC_GH_PATHS": "",
                ]
            )
        )

        do {
            _ = try await client.request(command: "unknown.command", as: EmptyTestingPayload.self)
            XCTFail("Expected unknown command error.")
        } catch BackendClientError.helperError(let error) {
            XCTAssertEqual(error.code, "protocol.unknownCommand")
            XCTAssertEqual(error.detail, "unknown.command")
        }

        await client.close()
    }

    func testClientMapsMalformedJSONResponse() async throws {
        let helper = try writePythonHelper(
            contents: """
            print("not-json", flush=True)
            """
        )
        let client = AgendumBackendClient(configuration: fakeHelperConfiguration(helperURL: helper))

        do {
            _ = try await client.request(command: "malformed", as: EmptyTestingPayload.self)
            XCTFail("Expected invalid response error.")
        } catch BackendClientError.invalidResponse(let message) {
            XCTAssertEqual(message, "Backend helper response was not valid JSON.")
        }

        await client.close()
    }

    func testClientMapsMismatchedResponseID() async throws {
        let helper = try writePythonHelper(
            contents: """
            import json
            import sys

            for line in sys.stdin:
                print(json.dumps({
                    "version": 1,
                    "id": "wrong-id",
                    "ok": True,
                    "payload": {}
                }), flush=True)
            """
        )
        let client = AgendumBackendClient(configuration: fakeHelperConfiguration(helperURL: helper))

        do {
            _ = try await client.request(command: "mismatch", as: EmptyTestingPayload.self)
            XCTFail("Expected mismatched id error.")
        } catch BackendClientError.unexpectedResponseID(_, let actual) {
            XCTAssertEqual(actual, "wrong-id")
        }

        await client.close()
    }

    func testClientMapsUnsupportedProtocolVersion() async throws {
        let helper = try writePythonHelper(
            contents: """
            import json
            import sys

            for line in sys.stdin:
                request = json.loads(line)
                print(json.dumps({
                    "version": 2,
                    "id": request["id"],
                    "ok": True,
                    "payload": {}
                }), flush=True)
            """
        )
        let client = AgendumBackendClient(configuration: fakeHelperConfiguration(helperURL: helper))

        do {
            _ = try await client.request(command: "unsupported", as: EmptyTestingPayload.self)
            XCTFail("Expected unsupported version error.")
        } catch BackendClientError.unsupportedProtocolVersion(let version) {
            XCTAssertEqual(version, 2)
        }

        await client.close()
    }

    func testClientMapsHelperStderrWhenProcessExits() async throws {
        let helper = try writePythonHelper(
            contents: """
            import sys

            print("helper failed loudly", file=sys.stderr, flush=True)
            sys.exit(7)
            """
        )
        let client = AgendumBackendClient(configuration: fakeHelperConfiguration(helperURL: helper))

        do {
            _ = try await client.request(command: "crash", as: EmptyTestingPayload.self)
            XCTFail("Expected helper termination error.")
        } catch BackendClientError.helperTerminated(let stderr) {
            XCTAssertEqual(stderr, "helper failed loudly")
        }

        await client.close()
    }

    func testClientTimesOutAndCanRestartHelper() async throws {
        let stateFile = temporaryDirectory().appendingPathComponent("first-run")
        let helper = try writePythonHelper(
            contents: """
            import json
            import os
            import sys
            import time

            state_file = "\(stateFile.path)"
            if not os.path.exists(state_file):
                os.makedirs(os.path.dirname(state_file), exist_ok=True)
                open(state_file, "w").close()
                time.sleep(10)

            for line in sys.stdin:
                request = json.loads(line)
                print(json.dumps({
                    "version": 1,
                    "id": request["id"],
                    "ok": True,
                    "payload": {}
                }), flush=True)
            """
        )
        let client = AgendumBackendClient(
            configuration: fakeHelperConfiguration(helperURL: helper, requestTimeout: 0.1)
        )

        do {
            _ = try await client.request(command: "hang", as: EmptyTestingPayload.self)
            XCTFail("Expected timeout error.")
        } catch BackendClientError.requestTimedOut(let timeout) {
            XCTAssertEqual(timeout, 0.1)
        }

        _ = try await client.request(command: "after-timeout", as: EmptyTestingPayload.self)
        await client.close()
    }

    func testDiscoverDevelopmentRepositoryRootResolvesThroughAppBundleLayout() throws {
        let fileManager = FileManager.default
        let tmp = fileManager.temporaryDirectory
            .appendingPathComponent("AgendumMacCoreTests")
            .appendingPathComponent(UUID().uuidString)
        defer { try? fileManager.removeItem(at: tmp) }

        let repoRoot = tmp.appendingPathComponent("repo")
        let backendDir = repoRoot.appendingPathComponent("Backend")
        let macOSDir = repoRoot
            .appendingPathComponent(".build")
            .appendingPathComponent("Agendum.app")
            .appendingPathComponent("Contents")
            .appendingPathComponent("MacOS")
        try fileManager.createDirectory(at: backendDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: macOSDir, withIntermediateDirectories: true)

        let helperMarker = backendDir.appendingPathComponent("agendum_backend_helper.py")
        fileManager.createFile(atPath: helperMarker.path, contents: Data())

        let executableURL = macOSDir.appendingPathComponent("Agendum")
        fileManager.createFile(atPath: executableURL.path, contents: Data())

        let unrelatedCwd = tmp.appendingPathComponent("unrelated")
        try fileManager.createDirectory(at: unrelatedCwd, withIntermediateDirectories: true)

        let resolved = BackendClientConfiguration.discoverDevelopmentRepositoryRoot(
            currentDirectoryURL: unrelatedCwd,
            executableURL: executableURL
        )

        XCTAssertEqual(
            resolved.resolvingSymlinksInPath().standardizedFileURL.path,
            repoRoot.resolvingSymlinksInPath().standardizedFileURL.path
        )
    }

    func testDiscoverDevelopmentRepositoryRootFallsBackToCurrentDirectoryWhenNoMarkerFound() throws {
        let fileManager = FileManager.default
        let tmp = fileManager.temporaryDirectory
            .appendingPathComponent("AgendumMacCoreTests")
            .appendingPathComponent(UUID().uuidString)
        defer { try? fileManager.removeItem(at: tmp) }

        let cwdRoot = tmp.appendingPathComponent("root")
        let binDir = tmp.appendingPathComponent("bin")
        try fileManager.createDirectory(at: cwdRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: binDir, withIntermediateDirectories: true)

        let executableURL = binDir.appendingPathComponent("binary")
        fileManager.createFile(atPath: executableURL.path, contents: Data())

        let resolved = BackendClientConfiguration.discoverDevelopmentRepositoryRoot(
            currentDirectoryURL: cwdRoot,
            executableURL: executableURL
        )

        XCTAssertEqual(
            resolved.resolvingSymlinksInPath().standardizedFileURL.path,
            cwdRoot.resolvingSymlinksInPath().standardizedFileURL.path
        )
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("AgendumMacCoreTests")
            .appendingPathComponent(UUID().uuidString)
    }

    private func writeExecutable(at url: URL, contents: String) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }

    private func writePythonHelper(contents: String) throws -> URL {
        let helper = temporaryDirectory().appendingPathComponent("helper.py")
        try FileManager.default.createDirectory(
            at: helper.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: helper, atomically: true, encoding: .utf8)
        return helper
    }

    private func fakeHelperConfiguration(
        helperURL: URL,
        requestTimeout: TimeInterval = 10
    ) -> BackendClientConfiguration {
        BackendClientConfiguration(
            helperURL: helperURL,
            workingDirectoryURL: repositoryRoot(),
            environment: [:],
            requestTimeout: requestTimeout
        )
    }
}

private struct EmptyTestingPayload: Decodable {}

private struct ProcessIDPayload: Decodable {
    let processID: Int
}
