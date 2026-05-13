@testable import AgendumAppServices
import AgendumFeature
import AgendumModel
import AgendumSync
import XCTest

final class NativeDashboardServiceTests: XCTestCase {
    func testWorkspaceSelectionCreatesNamespaceConfigAndListsWorkspaces() async throws {
        let root = try temporaryDirectory()
        let service = makeService(baseDirectory: root)

        let selection = try await service.selectWorkspace(namespace: "Example-Org")
        let listed = try await service.listWorkspaces()

        XCTAssertEqual(selection.workspace.id, "example-org")
        XCTAssertEqual(selection.workspace.namespace, "example-org")
        XCTAssertEqual(selection.workspace.displayName, "example-org")
        XCTAssertEqual(selection.workspace.configPath, root.appendingPathComponent("workspaces/example-org/config.toml").path)
        XCTAssertEqual(selection.workspace.dbPath, root.appendingPathComponent("workspaces/example-org/agendum.db").path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("workspaces/example-org/config.toml").path))
        XCTAssertEqual(listed.map(\.id), ["base", "example-org"])
        XCTAssertFalse(listed[0].isCurrent)
        XCTAssertTrue(listed[1].isCurrent)
    }

    func testAuthStatusUsesWorkspaceGhConfigDirAndRepairCommand() async throws {
        let root = try temporaryDirectory()
        let gh = root.appendingPathComponent("bin/gh")
        let service = makeService(
            baseDirectory: root,
            ghLocator: { gh },
            ghRunner: { _, arguments, environment, _ in
                XCTAssertEqual(arguments, ["auth", "status"])
                XCTAssertTrue(environment["GH_CONFIG_DIR"]?.hasSuffix("/workspaces/example-org/gh") == true)
                return ("", "not logged in", 1)
            }
        )

        _ = try await service.selectWorkspace(namespace: "example-org")
        let auth = try await service.authStatus()

        XCTAssertTrue(auth.ghFound)
        XCTAssertFalse(auth.authenticated)
        XCTAssertEqual(auth.ghPath, gh.path)
        XCTAssertTrue(auth.workspaceGhConfigDir.hasSuffix("/workspaces/example-org/gh"))
        XCTAssertTrue(auth.repairCommand?.contains("GH_CONFIG_DIR=") == true)
        XCTAssertTrue(auth.repairCommand?.contains("gh auth login") == true)
    }

    func testForceSyncRunsNativeSyncRunnerAndRecordsFinalStatus() async throws {
        let root = try temporaryDirectory()
        let service = makeService(
            baseDirectory: root,
            syncRunner: { paths, config in
                XCTAssertTrue(paths.dbPath.path.hasSuffix("/agendum.db"))
                XCTAssertEqual(config.orgs, ["example-org"])
                return SyncResult(changes: 3, hasAttentionItems: true)
            }
        )

        _ = try await service.selectWorkspace(namespace: "example-org")
        let status = try await service.forceSync()

        XCTAssertEqual(status.state, "idle")
        XCTAssertEqual(status.changes, 3)
        XCTAssertTrue(status.hasAttentionItems)
        XCTAssertNotNil(status.lastSyncAt)
    }

    func testForceSyncErrorRecordsErrorStatus() async throws {
        let root = try temporaryDirectory()
        let service = makeService(
            baseDirectory: root,
            syncRunner: { _, _ in
                SyncResult(changes: 0, hasAttentionItems: false, errorMessage: "gh credentials expired")
            }
        )

        let status = try await service.forceSync()

        XCTAssertEqual(status.state, "error")
        XCTAssertEqual(status.lastError, "gh credentials expired")
        XCTAssertEqual(status.changes, 0)
    }

    func testForceSyncThrowRecordsErrorStatusAndAllowsRetry() async throws {
        let root = try temporaryDirectory()
        let calls = CallCounter()
        let service = makeService(
            baseDirectory: root,
            syncRunner: { _, _ in
                let call = await calls.bump()
                if call == 1 {
                    throw DashboardServiceError(code: "sync.boom", message: "store unavailable")
                }
                return SyncResult(changes: 2, hasAttentionItems: false)
            }
        )

        do {
            _ = try await service.forceSync()
            XCTFail("expected thrown sync failure")
        } catch let error as DashboardServiceError {
            XCTAssertEqual(error.message, "store unavailable")
        }

        let failed = try await service.syncStatus()
        XCTAssertEqual(failed.state, "error")
        XCTAssertEqual(failed.lastError, "store unavailable")

        let retried = try await service.forceSync()
        XCTAssertEqual(retried.state, "idle")
        XCTAssertEqual(retried.changes, 2)
        let callCount = await calls.count()
        XCTAssertEqual(callCount, 2)
    }
}

private actor CallCounter {
    private(set) var value = 0

    func bump() -> Int {
        value += 1
        return value
    }

    func count() -> Int {
        value
    }
}

private func makeService(
    baseDirectory: URL,
    ghLocator: @escaping @Sendable () -> URL? = { nil },
    ghRunner: @escaping NativeDashboardService.ProcessRunner = { _, _, _, _ in ("", "", 0) },
    usernameProvider: @escaping NativeDashboardService.UsernameProvider = { _ in "dan" },
    syncRunner: @escaping NativeDashboardService.SyncRunner = { _, _ in SyncResult() }
) -> NativeDashboardService {
    NativeDashboardService(
        baseDirectory: baseDirectory,
        ghLocator: ghLocator,
        ghRunner: ghRunner,
        usernameProvider: usernameProvider,
        syncRunner: syncRunner
    )
}

private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("AgendumAppServicesTests")
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
