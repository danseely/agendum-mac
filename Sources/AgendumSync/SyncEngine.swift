import Foundation
import AgendumGitHub
import AgendumMacStore

public protocol SyncGitHubClient: RepoFetchClient, ReviewFetchClient {
    func currentUserLogin() async throws -> String
}

extension GitHubClient: SyncGitHubClient {}

public protocol SyncTaskStore: SyncTaskWriter {
    func activeSyncTasks() async throws -> [ExistingTask]
}

extension TaskStore: SyncTaskStore {
    public func activeSyncTasks() async throws -> [ExistingTask] {
        try await activeSyncTaskRecords().compactMap { record in
            guard let id = record.id else { return nil }
            return ExistingTask(
                id: Int(id),
                title: record.title,
                source: record.source,
                status: record.status,
                ghURL: record.ghURL,
                ghRepo: record.ghRepo,
                project: record.project,
                ghAuthor: record.ghAuthor,
                ghAuthorName: record.ghAuthorName,
                tags: record.tags
            )
        }
    }
}

public struct SyncResult: Equatable, Sendable {
    public var changes: Int
    public var hasAttentionItems: Bool
    public var errorMessage: String?

    public init(changes: Int = 0, hasAttentionItems: Bool = false, errorMessage: String? = nil) {
        self.changes = changes
        self.hasAttentionItems = hasAttentionItems
        self.errorMessage = errorMessage
    }
}

public struct SyncAuthenticationFailedError: Error, Equatable, Sendable {}

public struct SyncEngine: Sendable {
    private let client: any SyncGitHubClient
    private let store: any SyncTaskStore
    private let maxRepoFetchConcurrency: Int
    private let now: @Sendable () -> String

    public init(
        client: any SyncGitHubClient,
        store: any SyncTaskStore,
        maxRepoFetchConcurrency: Int = RepoFetcher.defaultMaxConcurrent,
        now: @escaping @Sendable () -> String = { defaultSyncTimestamp() }
    ) {
        self.client = client
        self.store = store
        self.maxRepoFetchConcurrency = maxRepoFetchConcurrency
        self.now = now
    }

    /// One-shot Swift sync orchestration. Mirrors `syncer.py:102-395` minus
    /// the `/notifications` overlay, which is an explicit MVP cut.
    public func run(config: WorkspaceConfig) async -> SyncResult {
        let repoConfig = config.repoConfig
        guard !repoConfig.orgs.isEmpty || !repoConfig.repos.isEmpty else {
            logger.warning("SyncEngine: no orgs or repos configured; skipping sync")
            return SyncResult()
        }

        do {
            let ghUser = try await client.currentUserLogin()
            guard !ghUser.isEmpty else {
                logger.error("SyncEngine: could not determine GitHub username")
                return SyncResult(errorMessage: "gh credentials expired")
            }

            let repoFetcher = RepoFetcher(client: client, maxConcurrent: maxRepoFetchConcurrency)
            let repoResult = try await repoFetcher.run(config: repoConfig, ghUser: ghUser)
            let reviewResult = await fetchReviewTasks(config: repoConfig, user: ghUser, client: client)
            if !reviewResult.reviewFetchOK {
                logger.warning("SyncEngine: review PR discovery incomplete; skipping review cleanup")
            }

            let existing = try await store.activeSyncTasks()
            let diff = diffTasks(
                existing: existing,
                incoming: repoResult.incoming + reviewResult.incoming,
                fetchedRepos: repoResult.fetchedRepos,
                reviewFetchOK: reviewResult.reviewFetchOK
            )
            let applied = try await applyDiff(diff, store: store, now: now())
            logger.info("SyncEngine complete: \(applied.changes, privacy: .public) changes, attention=\(applied.attention, privacy: .public)")
            return SyncResult(changes: applied.changes, hasAttentionItems: applied.attention)
        } catch {
            logger.error("SyncEngine failed: \(String(describing: error), privacy: .public)")
            return SyncResult(errorMessage: syncErrorMessage(for: error))
        }
    }
}

private func syncErrorMessage(for error: any Error) -> String {
    if error is SyncAuthenticationFailedError {
        return "gh credentials expired"
    }
    if let githubError = error as? GitHubClientError {
        switch githubError {
        case .authFailed, .unauthorized:
            return "gh credentials expired"
        default:
            break
        }
    }
    return String(describing: error)
}
