import AgendumFeature
import AgendumGitHub
import AgendumMacStore
import AgendumModel
import AgendumSync
import Foundation

public actor NativeDashboardService: DashboardServicing {
    typealias ProcessRunner = @Sendable (
        URL,
        [String],
        [String: String],
        Duration
    ) async throws -> (stdout: String, stderr: String, exitCode: Int32)
    typealias UsernameProvider = @Sendable (URL) async -> String?
    typealias SyncRunner = @Sendable (WorkspaceRuntimePaths, WorkspaceConfig) async throws -> SyncResult

    private let baseDirectory: URL
    private let ghLocator: @Sendable () -> URL?
    private let ghRunner: ProcessRunner
    private let usernameProvider: UsernameProvider
    private let syncRunner: SyncRunner
    private var namespace: String?
    private var status = SyncStatus.idle
    private var syncToken = 0

    public init(
        baseDirectory: URL = NativeDashboardService.defaultBaseDirectory()
    ) {
        self.init(
            baseDirectory: baseDirectory,
            ghLocator: { GhCLITokenProvider.locateGhBinary() },
            ghRunner: { executable, arguments, environment, deadline in
                try await GhCLITokenProvider.runProcessWithDeadline(
                    executableURL: executable,
                    arguments: arguments,
                    environment: environment,
                    deadline: deadline
                )
            },
            usernameProvider: { ghConfigDir in
                try? await GitHubClient(
                    tokenProvider: GhCLITokenProvider(ghConfigDir: ghConfigDir)
                ).currentUserLogin()
            },
            syncRunner: { paths, config in
                let store = try TaskStore(path: paths.dbPath)
                let tokenProvider = GhCLITokenProvider(ghConfigDir: paths.ghConfigDir)
                let client = GitHubClient(tokenProvider: tokenProvider)
                let engine = SyncEngine(client: client, store: store)
                return await engine.run(config: config)
            }
        )
    }

    init(
        baseDirectory: URL,
        ghLocator: @escaping @Sendable () -> URL?,
        ghRunner: @escaping ProcessRunner,
        usernameProvider: @escaping UsernameProvider,
        syncRunner: @escaping SyncRunner
    ) {
        self.baseDirectory = baseDirectory
        self.ghLocator = ghLocator
        self.ghRunner = ghRunner
        self.usernameProvider = usernameProvider
        self.syncRunner = syncRunner
    }

    public func currentWorkspace() async throws -> Workspace {
        try workspacePayload(namespace: namespace, isCurrent: true, ensureConfig: true)
    }

    public func listWorkspaces() async throws -> [Workspace] {
        var result = [
            try workspacePayload(namespace: nil, isCurrent: namespace == nil, ensureConfig: false)
        ]
        let workspacesDirectory = baseDirectory.appendingPathComponent("workspaces")
        let children = (try? FileManager.default.contentsOfDirectory(
            at: workspacesDirectory,
            includingPropertiesForKeys: [.isDirectoryKey]
        )) ?? []

        for child in children.sorted(by: { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }) {
            let values = try? child.resourceValues(forKeys: [.isDirectoryKey])
            guard values?.isDirectory == true else { continue }
            guard let normalized = try? WorkspaceRuntimePaths.normalizeNamespace(child.lastPathComponent) else {
                continue
            }
            result.append(try workspacePayload(
                namespace: normalized,
                isCurrent: normalized == namespace,
                ensureConfig: false
            ))
        }
        return result
    }

    public func selectWorkspace(namespace: String?) async throws -> WorkspaceSelection {
        let normalized = try mapWorkspaceError {
            try WorkspaceRuntimePaths.normalizeNamespace(namespace)
        }
        let paths = try mapWorkspaceError {
            try WorkspaceRuntimePaths.workspace(namespace: normalized, baseDirectory: baseDirectory)
        }
        _ = try mapWorkspaceError {
            try WorkspaceConfig.ensure(paths: paths, namespace: normalized)
        }

        self.namespace = normalized.map { _ in paths.workspaceRoot.lastPathComponent }
        syncToken += 1
        status = .idle

        return WorkspaceSelection(
            workspace: try await currentWorkspace(),
            auth: try await authStatus(),
            sync: try await syncStatus()
        )
    }

    public func syncStatus() async throws -> SyncStatus {
        status
    }

    public func forceSync() async throws -> SyncStatus {
        if status.state == "running" {
            return status
        }

        let paths = try currentPaths()
        let config = try mapWorkspaceError {
            try WorkspaceConfig.ensure(paths: paths, namespace: namespace)
        }
        syncToken += 1
        let token = syncToken
        status = SyncStatus(
            state: "running",
            lastSyncAt: status.lastSyncAt,
            lastError: nil,
            changes: 0,
            hasAttentionItems: false
        )

        let result: SyncResult
        do {
            result = try await syncRunner(paths, config)
        } catch {
            let mapped = serviceError(code: "sync.failed", error: error)
            if token == syncToken {
                status = SyncStatus(
                    state: "error",
                    lastSyncAt: status.lastSyncAt,
                    lastError: mapped.message,
                    changes: 0,
                    hasAttentionItems: false
                )
            }
            throw mapped
        }
        let completed = SyncStatus(
            state: result.errorMessage == nil ? "idle" : "error",
            lastSyncAt: defaultSyncTimestamp(),
            lastError: result.errorMessage,
            changes: result.changes,
            hasAttentionItems: result.hasAttentionItems
        )
        if token == syncToken {
            status = completed
        }
        return status
    }

    public func authStatus() async throws -> AuthStatus {
        let paths = try currentPaths()
        _ = try mapWorkspaceError {
            try WorkspaceConfig.ensure(paths: paths, namespace: namespace)
        }
        try? FileManager.default.createDirectory(
            at: paths.ghConfigDir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        guard let ghURL = ghLocator() else {
            return AuthStatus(
                ghFound: false,
                ghPath: nil,
                authenticated: false,
                username: nil,
                workspaceGhConfigDir: displayPath(paths.ghConfigDir),
                repairInstructions: "Install GitHub CLI with Homebrew, then authenticate with gh auth login.",
                repairCommand: nil
            )
        }

        var environment = ProcessInfo.processInfo.environment
        environment["GH_CONFIG_DIR"] = paths.ghConfigDir.path
        let auth: (stdout: String, stderr: String, exitCode: Int32)
        do {
            auth = try await ghRunner(ghURL, ["auth", "status"], environment, .seconds(10))
        } catch {
            throw serviceError(code: "auth.statusFailed", error: error)
        }
        if auth.exitCode != 0 {
            let command = repairCommand(ghConfigDir: paths.ghConfigDir)
            return AuthStatus(
                ghFound: true,
                ghPath: ghURL.path,
                authenticated: false,
                username: nil,
                workspaceGhConfigDir: displayPath(paths.ghConfigDir),
                repairInstructions: "Run \(command) in Terminal.",
                repairCommand: command
            )
        }

        let username = await usernameProvider(paths.ghConfigDir)
        return AuthStatus(
            ghFound: true,
            ghPath: ghURL.path,
            authenticated: true,
            username: username,
            workspaceGhConfigDir: displayPath(paths.ghConfigDir),
            repairInstructions: nil,
            repairCommand: nil
        )
    }

    public func authDiagnose() async throws -> AuthDiagnostics {
        let ghURL = ghLocator()
        let version: String?
        if let ghURL {
            let result = try? await ghRunner(ghURL, ["--version"], ProcessInfo.processInfo.environment, .seconds(5))
            version = result?.stdout.split(separator: "\n").first.map(String.init)
        } else {
            version = nil
        }
        return AuthDiagnostics(
            gh: .init(
                found: ghURL != nil,
                path: ghURL?.path,
                version: version,
                installed: ghURL != nil
            ),
            auth: try await authStatus(),
            host: "github.com",
            pathEntries: []
        )
    }

    private func currentPaths() throws -> WorkspaceRuntimePaths {
        try mapWorkspaceError {
            try WorkspaceRuntimePaths.workspace(namespace: namespace, baseDirectory: baseDirectory)
        }
    }

    private func workspacePayload(
        namespace: String?,
        isCurrent: Bool,
        ensureConfig: Bool
    ) throws -> Workspace {
        let paths = try mapWorkspaceError {
            try WorkspaceRuntimePaths.workspace(namespace: namespace, baseDirectory: baseDirectory)
        }
        if ensureConfig {
            _ = try mapWorkspaceError {
                try WorkspaceConfig.ensure(paths: paths, namespace: namespace)
            }
        }
        return Workspace(
            id: namespace ?? "base",
            namespace: namespace,
            displayName: namespace ?? "Base Workspace",
            configPath: paths.configPath.path,
            dbPath: paths.dbPath.path,
            isCurrent: isCurrent
        )
    }

    public static func defaultBaseDirectory() -> URL {
        if let override = ProcessInfo.processInfo.environment["AGENDUM_MAC_BASE_DIR"],
           !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: NSString(string: override).expandingTildeInPath)
        }
        return WorkspaceRuntimePaths.defaultBaseDirectory()
    }
}

private extension SyncStatus {
    static let idle = SyncStatus(
        state: "idle",
        lastSyncAt: nil,
        lastError: nil,
        changes: 0,
        hasAttentionItems: false
    )
}

private func mapWorkspaceError<T>(_ operation: () throws -> T) throws -> T {
    do {
        return try operation()
    } catch let error as DashboardServiceError {
        throw error
    } catch {
        throw DashboardServiceError(
            code: "workspace.invalid",
            message: error.localizedDescription,
            recovery: "Check the workspace name or config file, then try again."
        )
    }
}

private func mapServiceError<T>(
    code: String,
    _ operation: () throws -> T
) throws -> T {
    do {
        return try operation()
    } catch let error as DashboardServiceError {
        throw error
    } catch {
        throw DashboardServiceError(
            code: code,
            message: String(describing: error),
            recovery: "Try again from the dashboard. If it keeps failing, run GitHub CLI diagnostics in Settings."
        )
    }
}

private func serviceError(code: String, error: any Error) -> DashboardServiceError {
    if let error = error as? DashboardServiceError {
        return error
    }
    return DashboardServiceError(
        code: code,
        message: String(describing: error),
        recovery: "Try again from the dashboard. If it keeps failing, run GitHub CLI diagnostics in Settings."
    )
}

private func repairCommand(ghConfigDir: URL) -> String {
    "GH_CONFIG_DIR=\(shellQuote(ghConfigDir.path)) gh auth login"
}

private func shellQuote(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
}

private func displayPath(_ url: URL) -> String {
    let path = url.path
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    if path == home {
        return "~"
    }
    if path.hasPrefix(home + "/") {
        return "~/" + path.dropFirst(home.count + 1)
    }
    return path
}
