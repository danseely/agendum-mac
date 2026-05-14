import Foundation

/// Bearer-token provider for the GitHub API. Through MVP we delegate to the
/// installed `gh` CLI (`gh auth token`) — native OAuth Device Flow + Keychain
/// is post-MVP (deferred B4).
///
/// The token is cached after the first successful read so the GitHub client
/// doesn't spawn a subprocess per request. Callers signal a forced refresh
/// (e.g., after a 401 response) by calling `invalidate()`.
public protocol GitHubTokenProviding: Sendable {
    /// Returns a non-empty bearer token, refreshing from the source if no
    /// cached value is available. Throws if the token can't be obtained.
    func token() async throws -> String
    /// Drops the cached token so the next `token()` call re-reads from source.
    func invalidate() async
}

public enum GitHubAuthError: Error, Equatable, Sendable, CustomStringConvertible {
    case ghCLINotFound
    case ghCLIFailed(stderr: String, exitCode: Int32)
    case emptyToken
    case ghCLITimedOut

    public var description: String {
        switch self {
        case .ghCLINotFound:
            return "GitHub CLI (`gh`) not found. Install it from https://cli.github.com/ or sign in via Settings. (Looked in /opt/homebrew/bin, /usr/local/bin, /usr/bin, /opt/local/bin.)"
        case .ghCLIFailed(let stderr, let exitCode):
            let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return "`gh auth token` exited \(exitCode)\(trimmed.isEmpty ? "" : ": \(trimmed)")."
        case .emptyToken:
            return "`gh auth token` returned an empty token. Run `gh auth login` to sign in."
        case .ghCLITimedOut:
            return "`gh auth token` did not respond within the deadline. Try `gh auth status` from the terminal to debug."
        }
    }
}

/// Default `GitHubTokenProviding` that reads the bearer via `gh auth token`.
/// The subprocess invocation closure is injectable so tests can stub it.
public actor GhCLITokenProvider: GitHubTokenProviding {
    /// Async closure that runs `gh auth token` and returns `(stdout, stderr, exitCode)`.
    public typealias Runner = @Sendable () async throws -> (stdout: String, stderr: String, exitCode: Int32)

    private let runner: Runner
    private var cached: String?

    public init(runner: @escaping Runner = GhCLITokenProvider.defaultRunner) {
        self.runner = runner
    }

    public init(ghConfigDir: URL?) {
        self.runner = GhCLITokenProvider.runner(ghConfigDir: ghConfigDir)
    }

    public func token() async throws -> String {
        if let cached, !cached.isEmpty { return cached }
        let result: (stdout: String, stderr: String, exitCode: Int32)
        do {
            result = try await runner()
        } catch let posix as POSIXError where posix.code == .ENOENT {
            throw GitHubAuthError.ghCLINotFound
        } catch CocoaError.fileNoSuchFile {
            throw GitHubAuthError.ghCLINotFound
        } catch is GhRunnerTimeout {
            throw GitHubAuthError.ghCLITimedOut
        }
        if result.exitCode != 0 {
            throw GitHubAuthError.ghCLIFailed(stderr: result.stderr, exitCode: result.exitCode)
        }
        let token = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw GitHubAuthError.emptyToken }
        cached = token
        return token
    }

    public func invalidate() async {
        cached = nil
    }

    // MARK: - Default runner

    /// Runs `gh auth token` via Foundation's `Process`. Searches a short list of
    /// canonical install paths for the `gh` binary; throws `ghCLINotFound` if
    /// none are present rather than relying on a fragile PATH lookup.
    /// Bounded by a 10s deadline so a stuck `gh` (interactive prompt, keychain
    /// hang) doesn't stall sync indefinitely.
    public static let defaultRunner: Runner = {
        try await runner(ghConfigDir: nil)()
    }

    public static func runner(ghConfigDir: URL?) -> Runner {
        {
            guard let ghURL = locateGhBinary() else {
                throw POSIXError(.ENOENT)
            }
            var environment = ProcessInfo.processInfo.environment
            if let ghConfigDir {
                environment["GH_CONFIG_DIR"] = ghConfigDir.path
            }
            return try await runProcessWithDeadline(
                executableURL: ghURL,
                arguments: ["auth", "token"],
                environment: environment,
                deadline: .seconds(10)
            )
        }
    }

    public static func locateGhBinary() -> URL? {
        let candidates = [
            "/opt/homebrew/bin/gh",
            "/usr/local/bin/gh",
            "/usr/bin/gh",
            "/opt/local/bin/gh", // MacPorts
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    public static func runProcessWithDeadline(
        executableURL: URL,
        arguments: [String],
        environment: [String: String] = ProcessInfo.processInfo.environment,
        deadline: Duration
    ) async throws -> (stdout: String, stderr: String, exitCode: Int32) {
        // Process/Pipe are non-Sendable classes. We confine all access to one
        // detached task and use a sibling deadline task to terminate-on-timeout.
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            process.executableURL = executableURL
            process.arguments = arguments
            process.environment = environment
            do {
                try process.run()
            } catch let error as NSError where error.domain == NSPOSIXErrorDomain && error.code == ENOENT {
                throw POSIXError(.ENOENT)
            }

            // Deadline task: SIGTERM the child if the deadline expires.
            let watchdog = TimeoutWatchdog(process: process)
            let deadlineTask = Task {
                do {
                    try await Task.sleep(for: deadline)
                } catch {
                    return
                }
                watchdog.fireIfStillRunning()
            }
            defer { deadlineTask.cancel() }

            process.waitUntilExit()
            let didTimeOut = watchdog.didFire
            let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            if didTimeOut {
                throw GhRunnerTimeout()
            }
            return (stdout, stderr, process.terminationStatus)
        }.value
    }

    struct GhRunnerTimeout: Error, Sendable {}

    /// Reference-typed flag wrapping a child `Process`, accessible from the
    /// deadline `Task` (different isolation than the spawning detached task).
    /// We use a class so the boolean mutation + the `terminate()` call are
    /// visible to the spawning task when it inspects `didFire`.
    final class TimeoutWatchdog: @unchecked Sendable {
        private let lock = NSLock()
        private let process: Process
        private var _didFire: Bool = false

        init(process: Process) { self.process = process }

        func fireIfStillRunning() {
            lock.lock(); defer { lock.unlock() }
            guard process.isRunning else { return }
            process.terminate()
            _didFire = true
        }

        var didFire: Bool {
            lock.lock(); defer { lock.unlock() }
            return _didFire
        }
    }

}
