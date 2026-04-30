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
            _ = try await client.request(command: "task.list", as: EmptyTestingPayload.self)
            XCTFail("Expected unknown command error.")
        } catch BackendClientError.helperError(let error) {
            XCTAssertEqual(error.code, "protocol.unknownCommand")
            XCTAssertEqual(error.detail, "task.list")
        }

        await client.close()
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
}

private struct EmptyTestingPayload: Decodable {}
