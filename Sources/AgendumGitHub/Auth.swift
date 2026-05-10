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

    public var description: String {
        switch self {
        case .ghCLINotFound:
            return "GitHub CLI (`gh`) not found. Install it from https://cli.github.com/ or sign in via Settings."
        case .ghCLIFailed(let stderr, let exitCode):
            let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return "`gh auth token` exited \(exitCode)\(trimmed.isEmpty ? "" : ": \(trimmed)")."
        case .emptyToken:
            return "`gh auth token` returned an empty token. Run `gh auth login` to sign in."
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

    public func token() async throws -> String {
        if let cached, !cached.isEmpty { return cached }
        let result: (stdout: String, stderr: String, exitCode: Int32)
        do {
            result = try await runner()
        } catch let posix as POSIXError where posix.code == .ENOENT {
            throw GitHubAuthError.ghCLINotFound
        } catch CocoaError.fileNoSuchFile {
            throw GitHubAuthError.ghCLINotFound
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
    public static let defaultRunner: Runner = {
        try await Task.detached(priority: .userInitiated) {
            guard let ghURL = locateGhBinary() else {
                throw POSIXError(.ENOENT)
            }
            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            process.executableURL = ghURL
            process.arguments = ["auth", "token"]
            do {
                try process.run()
            } catch let error as NSError where error.domain == NSPOSIXErrorDomain && error.code == ENOENT {
                throw POSIXError(.ENOENT)
            }
            process.waitUntilExit()
            let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            return (stdout, stderr, process.terminationStatus)
        }.value
    }

    private static func locateGhBinary() -> URL? {
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
}
