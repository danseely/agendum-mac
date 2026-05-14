import Foundation
import AgendumGitHub

// MARK: - Workspace config (slice the syncer needs from config.toml)

/// Minimal slice of workspace config the per-repo fan-out cares about.
/// Real `config.toml` loading lives in `WorkspaceConfig.swift` (next slice);
/// the fetcher stays decoupled from the loader.
public struct WorkspaceRepoConfig: Equatable, Sendable {
    /// Explicit `owner/name` list. When non-empty, repo discovery is skipped.
    public var repos: [String]
    /// Org logins to drive `discoverRepos` when `repos` is empty.
    public var orgs: [String]
    /// `owner/name` strings to subtract from the resolved set.
    public var excludeRepos: Set<String>

    public init(repos: [String] = [], orgs: [String] = [], excludeRepos: Set<String> = []) {
        self.repos = repos
        self.orgs = orgs
        self.excludeRepos = excludeRepos
    }
}

// MARK: - GitHub seam

/// Narrow seam over `GitHubClient` covering exactly the calls `RepoFetcher`
/// makes. Owned by `AgendumSync` (the consumer); `GitHubClient` conforms via
/// the extension below. Tests substitute a fake without needing URLSession.
public protocol RepoFetchClient: Sendable {
    func discoverRepos(orgs: [String], user: String) async throws -> [String]
    func fetchRepoData(owner: String, name: String, user: String) async throws
        -> (data: GHRepoQueryData, partialErrors: [GHGraphQLError])
}

extension GitHubClient: RepoFetchClient {}

// MARK: - Result

/// Output of `RepoFetcher.run`:
/// - `incoming`: every per-repo `IncomingTask` produced this cycle, in
///   completion order (the diff doesn't care about order).
/// - `fetchedRepos`: `owner/name` set for repos that responded with a
///   non-archived payload. Drives `diffTasks`'s partial-fetch guard
///   (syncer-spec §4 step 5).
/// - `partialErrors`: per-repo GraphQL `errors[]` arrays for diagnostic
///   surfacing. Empty payload + errors does NOT add the repo to
///   `fetchedRepos` — matches Python `gh.fetch_repo_data` returning {} on
///   transport failure.
public struct RepoFetchResult: Equatable, Sendable {
    public var incoming: [IncomingTask]
    public var fetchedRepos: Set<String>
    public var partialErrors: [String: [GHGraphQLError]]

    public init(
        incoming: [IncomingTask] = [],
        fetchedRepos: Set<String> = [],
        partialErrors: [String: [GHGraphQLError]] = [:]
    ) {
        self.incoming = incoming
        self.fetchedRepos = fetchedRepos
        self.partialErrors = partialErrors
    }
}

// MARK: - Fetcher

/// Per-repo GraphQL fan-out — port of the `syncer.py:131-259` middle.
///
/// Concurrency: `AsyncSemaphore(8)` (Python uses `asyncio.Semaphore(8)`).
/// User runs against a 150+-repo work org, so serial fetch would be punishing.
/// Per-repo failures (network, 5xx, archived, malformed payload) are isolated:
/// the failing repo is dropped from `fetchedRepos`, the cycle keeps going, and
/// `diffTasks` will refuse to close that repo's existing rows (partial-fetch
/// guard, spec §4 step 5).
public struct RepoFetcher: Sendable {
    /// Semaphore cap. Matches Python `Semaphore(8)`. Configurable for tests.
    public static let defaultMaxConcurrent = 8

    private let client: any RepoFetchClient
    private let maxConcurrent: Int

    public init(client: any RepoFetchClient, maxConcurrent: Int = defaultMaxConcurrent) {
        self.client = client
        self.maxConcurrent = maxConcurrent
    }

    /// Resolve target repos + fan-out + map. See spec §3.C and §3.D.
    public func run(config: WorkspaceRepoConfig, ghUser: String) async throws -> RepoFetchResult {
        // 1. Resolve target repos (spec §3.C).
        let resolvedRepos: [String]
        if !config.repos.isEmpty {
            resolvedRepos = config.repos
        } else if !config.orgs.isEmpty {
            resolvedRepos = try await client.discoverRepos(orgs: config.orgs, user: ghUser)
        } else {
            // Pre-flight should already have caught this (spec §3.A); be
            // defensive in case a caller skips that gate.
            return RepoFetchResult()
        }
        // Apply excludeRepos filter, dedupe, preserve first-seen order.
        var seen: Set<String> = []
        var targets: [String] = []
        for repo in resolvedRepos where !config.excludeRepos.contains(repo) && seen.insert(repo).inserted {
            targets.append(repo)
        }
        if targets.isEmpty { return RepoFetchResult() }

        // 2. Per-repo fan-out (spec §3.D), capped by AsyncSemaphore.
        let semaphore = AsyncSemaphore(value: maxConcurrent)
        let perRepoOutcomes = try await withThrowingTaskGroup(of: PerRepoOutcome.self) { group in
            for repoFullName in targets {
                group.addTask { [client] in
                    // `withPermit` acquires/releases around the body, mirrors
                    // Python `async with semaphore:`. Cancellation throws.
                    try await semaphore.withPermit {
                        await Self.fetchOne(
                            client: client,
                            repoFullName: repoFullName,
                            ghUser: ghUser
                        )
                    }
                }
            }
            var collected: [PerRepoOutcome] = []
            collected.reserveCapacity(targets.count)
            for try await outcome in group {
                collected.append(outcome)
            }
            return collected
        }

        // 3. Aggregate. Order doesn't matter for downstream diff/apply.
        var result = RepoFetchResult()
        for outcome in perRepoOutcomes {
            switch outcome.kind {
            case .success(let items):
                result.incoming.append(contentsOf: items)
                result.fetchedRepos.insert(outcome.repoFullName)
            case .archivedOrEmpty:
                // Skip — do NOT add to fetchedRepos so the partial-fetch
                // guard protects this repo's rows from close.
                break
            case .failed:
                // Same treatment as archived/empty: don't claim this repo
                // was fetched. Per-repo error isolation is the whole point
                // of the per-repo close protection in syncer-spec §4.
                break
            }
            if !outcome.partialErrors.isEmpty {
                result.partialErrors[outcome.repoFullName] = outcome.partialErrors
            }
        }
        return result
    }

    // MARK: - Per-repo

    private struct PerRepoOutcome {
        var repoFullName: String
        var kind: Kind
        var partialErrors: [GHGraphQLError]

        enum Kind {
            case success([IncomingTask])
            case archivedOrEmpty
            case failed
        }
    }

    private static func fetchOne(
        client: any RepoFetchClient,
        repoFullName: String,
        ghUser: String
    ) async -> PerRepoOutcome {
        let parts = repoFullName.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else {
            // Malformed entry in config — log and treat as failed (don't
            // claim it as fetched).
            logger.error("RepoFetcher: malformed repo entry \(repoFullName, privacy: .public)")
            return PerRepoOutcome(repoFullName: repoFullName, kind: .failed, partialErrors: [])
        }
        let owner = String(parts[0])
        let name = String(parts[1])

        do {
            let (data, partialErrors) = try await client.fetchRepoData(owner: owner, name: name, user: ghUser)
            if let items = ResponseMapping.mapRepoData(data, repoFullName: repoFullName, ghUser: ghUser) {
                return PerRepoOutcome(repoFullName: repoFullName, kind: .success(items), partialErrors: partialErrors)
            } else {
                // Archived or null repository payload.
                return PerRepoOutcome(repoFullName: repoFullName, kind: .archivedOrEmpty, partialErrors: partialErrors)
            }
        } catch {
            // Per-repo fault tolerance (spec §3.D / §7). One repo's hiccup
            // must not abort the whole cycle.
            logger.error("RepoFetcher: \(repoFullName, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            return PerRepoOutcome(repoFullName: repoFullName, kind: .failed, partialErrors: [])
        }
    }
}
