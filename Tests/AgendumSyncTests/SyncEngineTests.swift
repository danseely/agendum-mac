import Foundation
import Testing
import AgendumGitHub
import AgendumModel
@testable import AgendumMacStore
@testable import AgendumSync

private actor FakeSyncClient: SyncGitHubClient {
    var login = "alice"
    var currentUserError: (any Error & Sendable)?
    var repoData: [String: GHRepoQueryData] = [:]
    var discoveredRepos: [String] = []
    var reviewDiscoveryOK = true
    private(set) var currentUserCalls = 0
    private(set) var discoverRepoCalls = 0
    private(set) var fetchRepoCalls: [String] = []
    private(set) var discoverReviewCalls = 0

    func setRepoData(_ repo: String, _ data: GHRepoQueryData) {
        repoData[repo] = data
    }

    func currentUserLogin() async throws -> String {
        currentUserCalls += 1
        if let currentUserError {
            throw currentUserError
        }
        return login
    }

    func discoverRepos(orgs: [String], user: String) async throws -> [String] {
        discoverRepoCalls += 1
        return discoveredRepos
    }

    func fetchRepoData(owner: String, name: String, user: String) async throws
        -> (data: GHRepoQueryData, partialErrors: [GHGraphQLError])
    {
        let key = "\(owner)/\(name)"
        fetchRepoCalls.append(key)
        if let data = repoData[key] {
            return (data, [])
        }
        return (try decodeRepoQueryData(emptyRepoJSON(repoFull: key)), [])
    }

    func discoverReviewPRs(orgs: [String], user: String) async throws -> (prs: [GHSearchItem], ok: Bool) {
        discoverReviewCalls += 1
        return ([], reviewDiscoveryOK)
    }

    func fetchReviewDetail(owner: String, name: String, number: Int) async throws
        -> (data: GHReviewQueryData, partialErrors: [GHGraphQLError])
    {
        throw DummySyncError()
    }
}

private actor FakeSyncStore: SyncTaskStore {
    enum Op: Equatable {
        case insert(title: String, source: String, status: String, ghURL: String?, now: String)
        case update(id: Int, status: String?, changedColumns: Set<String>, resetSeen: Bool, now: String)
    }

    var existing: [ExistingTask]
    private(set) var activeCalls = 0
    private(set) var findCalls: [String] = []
    private(set) var ops: [Op] = []
    private var existingIDsByURL: [String: Int]
    private var nextID = 100

    init(existing: [ExistingTask] = []) {
        self.existing = existing
        self.existingIDsByURL = Dictionary(
            uniqueKeysWithValues: existing.compactMap { task in
                task.ghURL.map { ($0, task.id) }
            }
        )
    }

    func activeSyncTasks() async throws -> [ExistingTask] {
        activeCalls += 1
        return existing
    }

    func findTaskID(forGHURL ghURL: String) async throws -> Int? {
        findCalls.append(ghURL)
        return existingIDsByURL[ghURL]
    }

    @discardableResult
    func insertSyncedTask(
        title: String,
        source: String,
        status: String,
        ghURL: String?,
        ghRepo: String?,
        ghNumber: Int?,
        ghAuthor: String?,
        ghAuthorName: String?,
        project: String?,
        tags: String?,
        now: String
    ) async throws -> Int {
        ops.append(.insert(title: title, source: source, status: status, ghURL: ghURL, now: now))
        let id = nextID
        nextID += 1
        if let ghURL { existingIDsByURL[ghURL] = id }
        return id
    }

    func applySyncUpdate(
        id: Int,
        title: String?,
        source: String?,
        status: String?,
        project: String?,
        ghRepo: String?,
        ghNumber: Int?,
        ghAuthor: String?,
        ghAuthorName: String?,
        tags: String?,
        changedColumns: Set<String>,
        resetSeen: Bool,
        now: String
    ) async throws {
        ops.append(.update(id: id, status: status, changedColumns: changedColumns, resetSeen: resetSeen, now: now))
    }
}

private struct DummySyncError: Error, Sendable {}

@Suite struct SyncEngineTests {

    @Test func emptyConfigReturnsNoOpWithoutTouchingDependencies() async throws {
        let client = FakeSyncClient()
        let store = FakeSyncStore()
        let engine = SyncEngine(client: client, store: store)

        let result = await engine.run(config: WorkspaceConfig())

        #expect(result == SyncResult())
        #expect(await client.currentUserCalls == 0)
        #expect(await store.activeCalls == 0)
    }

    @Test func emptyGitHubLoginReturnsCredentialError() async throws {
        let client = FakeSyncClient()
        await client.setLogin("")
        let store = FakeSyncStore()
        let engine = SyncEngine(client: client, store: store)

        let result = await engine.run(config: WorkspaceConfig(repos: ["octo/repo"]))

        #expect(result == SyncResult(errorMessage: "gh credentials expired"))
        #expect(await store.activeCalls == 0)
    }

    @Test func authErrorsFromCurrentUserLoginReturnCredentialExpired() async throws {
        let errors: [any Error & Sendable] = [
            GitHubClientError.unauthorized,
            GitHubClientError.authFailed(.emptyToken),
            SyncAuthenticationFailedError(),
        ]

        for error in errors {
            let client = FakeSyncClient()
            await client.setCurrentUserError(error)
            let store = FakeSyncStore()
            let engine = SyncEngine(client: client, store: store)

            let result = await engine.run(config: WorkspaceConfig(repos: ["octo/repo"]))

            #expect(result == SyncResult(errorMessage: "gh credentials expired"))
            #expect(await store.activeCalls == 0)
        }
    }

    @Test func nonAuthErrorsRemainSpecific() async throws {
        let client = FakeSyncClient()
        await client.setCurrentUserError(DummySyncError())
        let store = FakeSyncStore()
        let engine = SyncEngine(client: client, store: store)

        let result = await engine.run(config: WorkspaceConfig(repos: ["octo/repo"]))

        #expect(result == SyncResult(errorMessage: String(describing: DummySyncError())))
        #expect(await store.activeCalls == 0)
    }

    @Test func explicitRepoIssueIsInserted() async throws {
        let client = FakeSyncClient()
        await client.setRepoData(
            "octo/repo",
            try decodeRepoQueryData(repoWithOpenIssueJSON(issueNumber: 1, repoFull: "octo/repo"))
        )
        let store = FakeSyncStore()
        let engine = SyncEngine(client: client, store: store, now: { fixedNow })

        let result = await engine.run(config: WorkspaceConfig(repos: ["octo/repo"]))

        #expect(result == SyncResult(changes: 1))
        #expect(await client.discoverRepoCalls == 0)
        #expect(await client.fetchRepoCalls == ["octo/repo"])
        #expect(await store.activeCalls == 1)
        #expect(await store.ops == [
            .insert(
                title: "Issue 1",
                source: "issue",
                status: "open",
                ghURL: "https://github.com/octo/repo/issues/1",
                now: fixedNow
            )
        ])
    }

    @Test func fetchedRepoWithMissingExistingAuthoredPRClosesIt() async throws {
        let client = FakeSyncClient()
        await client.setRepoData("octo/repo", try decodeRepoQueryData(emptyRepoJSON(repoFull: "octo/repo")))
        let store = FakeSyncStore(existing: [
            ExistingTask(
                id: 7,
                title: "Old PR",
                source: "pr_authored",
                status: "open",
                ghURL: "https://github.com/octo/repo/pull/7",
                ghRepo: "octo/repo"
            )
        ])
        let engine = SyncEngine(client: client, store: store, now: { fixedNow })

        let result = await engine.run(config: WorkspaceConfig(repos: ["octo/repo"]))

        #expect(result == SyncResult(changes: 1))
        #expect(await store.ops == [
            .update(
                id: 7,
                status: "merged",
                changedColumns: ["status"],
                resetSeen: false,
                now: fixedNow
            )
        ])
    }

    @Test func repoOnlyWorkspaceDoesNotCloseExistingReviewTasks() async throws {
        let client = FakeSyncClient()
        await client.setRepoData("octo/repo", try decodeRepoQueryData(emptyRepoJSON(repoFull: "octo/repo")))
        let store = FakeSyncStore(existing: [
            ExistingTask(
                id: 9,
                title: "Review PR",
                source: "pr_review",
                status: "review requested",
                ghURL: "https://github.com/octo/repo/pull/9",
                ghRepo: "octo/repo"
            )
        ])
        let engine = SyncEngine(client: client, store: store, now: { fixedNow })

        let result = await engine.run(config: WorkspaceConfig(repos: ["octo/repo"]))

        #expect(result == SyncResult())
        #expect(await store.ops.isEmpty)
        #expect(await client.discoverReviewCalls == 0)
    }

    @Test func realTaskStoreSecondIdenticalRunIsIdempotentAndPreservesTimestamps() async throws {
        let client = FakeSyncClient()
        await client.setRepoData(
            "octo/repo",
            try decodeRepoQueryData(repoWithOpenIssueJSON(issueNumber: 1, repoFull: "octo/repo"))
        )
        let store = try TaskStore(path: temporaryDatabaseURL())
        let firstEngine = SyncEngine(client: client, store: store, now: { fixedNow })

        let firstResult = await firstEngine.run(config: WorkspaceConfig(repos: ["octo/repo"]))
        let firstRecord = try #require(try await store.activeSyncTaskRecords().first)

        let secondEngine = SyncEngine(client: client, store: store, now: { laterNow })
        let secondResult = await secondEngine.run(config: WorkspaceConfig(repos: ["octo/repo"]))
        let secondRecord = try #require(try await store.activeSyncTaskRecords().first)

        #expect(firstResult == SyncResult(changes: 1))
        #expect(secondResult == SyncResult())
        #expect(secondRecord.id == firstRecord.id)
        #expect(secondRecord.lastChangedAt == firstRecord.lastChangedAt)
        #expect(secondRecord.createdAt == firstRecord.createdAt)
        #expect(secondRecord.updatedAt == firstRecord.updatedAt)
        #expect(secondRecord.lastChangedAt == fixedNow)
        #expect(secondRecord.updatedAt == fixedNow)
    }
}

private let fixedNow = "2026-05-12T12:00:00.000000+00:00"
private let laterNow = "2026-05-12T12:05:00.000000+00:00"

private extension FakeSyncClient {
    func setLogin(_ value: String) {
        login = value
    }

    func setCurrentUserError(_ error: any Error & Sendable) {
        currentUserError = error
    }
}

private func decodeRepoQueryData(_ json: String) throws -> GHRepoQueryData {
    let data = Data(json.utf8)
    let envelope = try JSONDecoder().decode(GHGraphQLResponse<GHRepoQueryData>.self, from: data)
    guard let payload = envelope.data else {
        Issue.record("envelope missing data")
        throw DummySyncError()
    }
    return payload
}

private func emptyRepoJSON(repoFull: String) -> String {
    let name = repoFull.split(separator: "/", maxSplits: 1).last.map(String.init) ?? repoFull
    return #"""
    { "data": { "repository": {
        "isArchived": false,
        "name": "\#(name)",
        "openIssues": {"nodes": []},
        "closedIssues": {"nodes": []},
        "authoredPRs": {"nodes": []},
        "mergedPRs": {"nodes": []},
        "closedPRs": {"nodes": []}
    } } }
    """#
}

private func repoWithOpenIssueJSON(issueNumber: Int, repoFull: String) -> String {
    let name = repoFull.split(separator: "/", maxSplits: 1).last.map(String.init) ?? repoFull
    return #"""
    { "data": { "repository": {
        "isArchived": false,
        "name": "\#(name)",
        "openIssues": { "nodes": [
          { "number": \#(issueNumber), "title": "Issue \#(issueNumber)",
            "url": "https://github.com/\#(repoFull)/issues/\#(issueNumber)",
            "state": "OPEN",
            "timelineItems": {"nodes": []},
            "labels": {"nodes": []} }
        ] },
        "closedIssues": {"nodes": []},
        "authoredPRs": {"nodes": []},
        "mergedPRs": {"nodes": []},
        "closedPRs": {"nodes": []}
    } } }
    """#
}

private func temporaryDatabaseURL() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("agendum-sync-engine-tests")
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent("agendum.db")
}
