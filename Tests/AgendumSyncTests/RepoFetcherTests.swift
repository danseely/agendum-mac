import Foundation
import Testing
import AgendumGitHub
@testable import AgendumSync

// MARK: - Fake client

/// Records every call and returns scripted payloads. Keyed on `owner/name`
/// for `fetchRepoData` and on the `orgs` list (joined) for `discoverRepos`.
private actor FakeRepoClient: RepoFetchClient {
    enum FetchOutcome {
        case success(GHRepoQueryData, partialErrors: [GHGraphQLError] = [])
        case failure(Error)
    }

    var fetchOutcomes: [String: FetchOutcome] = [:]
    var discoverOutcome: Result<[String], Error> = .success([])

    /// Per-repo recorded order (each call is appended). Useful to assert that
    /// every targeted repo was actually attempted.
    private(set) var fetchCalls: [String] = []
    private(set) var discoverCalls: Int = 0
    /// Tracks max in-flight fetches across the cycle, to verify the
    /// AsyncSemaphore cap.
    private(set) var maxConcurrent: Int = 0
    private var inflight: Int = 0

    func setFetch(_ repoFullName: String, _ outcome: FetchOutcome) {
        fetchOutcomes[repoFullName] = outcome
    }
    func setDiscover(_ repos: [String]) { discoverOutcome = .success(repos) }
    func setDiscover(_ error: Error) { discoverOutcome = .failure(error) }

    func discoverRepos(orgs: [String], user: String) async throws -> [String] {
        discoverCalls += 1
        switch discoverOutcome {
        case .success(let r): return r
        case .failure(let e): throw e
        }
    }

    private static func nullRepositoryPayload() throws -> GHRepoQueryData {
        try decodeRepoQueryData(#"{"data":{"repository":null}}"#)
    }

    func fetchRepoData(owner: String, name: String, user: String) async throws
        -> (data: GHRepoQueryData, partialErrors: [GHGraphQLError])
    {
        let key = "\(owner)/\(name)"
        fetchCalls.append(key)
        inflight += 1
        if inflight > maxConcurrent { maxConcurrent = inflight }
        // Yield so concurrent waves can ramp up before any one finishes,
        // making the maxConcurrent assertion reliable in the throttle test.
        await Task.yield()
        defer { inflight -= 1 }
        guard let outcome = fetchOutcomes[key] else {
            // Default: null `repository` (treated as archived/empty by
            // ResponseMapping → archivedOrEmpty).
            return (try Self.nullRepositoryPayload(), [])
        }
        switch outcome {
        case .success(let data, let errs): return (data, errs)
        case .failure(let e): throw e
        }
    }
}

// MARK: - Helpers

private func decodeRepoQueryData(_ json: String) throws -> GHRepoQueryData {
    let data = Data(json.utf8)
    let envelope = try JSONDecoder().decode(GHGraphQLResponse<GHRepoQueryData>.self, from: data)
    guard let payload = envelope.data else {
        Issue.record("envelope missing data")
        throw NSError(domain: "fixture", code: 0)
    }
    return payload
}

private struct DummyError: Error {}

/// Minimal repo payload for an archived repo.
private let archivedRepoJSON = #"""
{ "data": { "repository": {
    "isArchived": true,
    "openIssues": {"nodes": []}, "closedIssues": {"nodes": []},
    "authoredPRs": {"nodes": []}, "mergedPRs": {"nodes": []},
    "closedPRs": {"nodes": []}
} } }
"""#

/// Minimal repo payload for a successful (non-archived) repo with one open
/// issue assigned to the user. Just enough to verify the row flows through.
private func minimalRepoJSON(issueNumber: Int, repoFull: String) -> String {
    let parts = repoFull.split(separator: "/", maxSplits: 1)
    let shortName = String(parts[1])
    return #"""
    { "data": { "repository": {
        "isArchived": false,
        "name": "\#(shortName)",
        "openIssues": { "nodes": [
          { "number": \#(issueNumber), "title": "T",
            "url": "https://github.com/\#(repoFull)/issues/\#(issueNumber)",
            "state": "OPEN" }
        ] },
        "closedIssues": {"nodes": []},
        "authoredPRs": {"nodes": []},
        "mergedPRs": {"nodes": []},
        "closedPRs": {"nodes": []}
    } } }
    """#
}

// MARK: - Tests

@Suite struct RepoFetcherTests {

    @Test func emptyConfigReturnsNoOpResult() async throws {
        let client = FakeRepoClient()
        let fetcher = RepoFetcher(client: client)
        let result = try await fetcher.run(config: WorkspaceRepoConfig(), ghUser: "alice")
        #expect(result.incoming.isEmpty)
        #expect(result.fetchedRepos.isEmpty)
        #expect(await client.discoverCalls == 0)
        #expect(await client.fetchCalls.isEmpty)
    }

    @Test func explicitReposBypassesDiscovery() async throws {
        let client = FakeRepoClient()
        let json = minimalRepoJSON(issueNumber: 1, repoFull: "octo/repo")
        await client.setFetch("octo/repo", .success(try decodeRepoQueryData(json)))
        let fetcher = RepoFetcher(client: client)
        let cfg = WorkspaceRepoConfig(repos: ["octo/repo"], orgs: ["unused"])

        let result = try await fetcher.run(config: cfg, ghUser: "alice")

        #expect(await client.discoverCalls == 0, "discover must not run when repos is non-empty")
        #expect(result.fetchedRepos == ["octo/repo"])
        #expect(result.incoming.count == 1)
    }

    @Test func discoverDrivesTargetSetWhenReposEmpty() async throws {
        let client = FakeRepoClient()
        await client.setDiscover(["octo/a", "octo/b"])
        await client.setFetch("octo/a", .success(try decodeRepoQueryData(minimalRepoJSON(issueNumber: 1, repoFull: "octo/a"))))
        await client.setFetch("octo/b", .success(try decodeRepoQueryData(minimalRepoJSON(issueNumber: 2, repoFull: "octo/b"))))

        let fetcher = RepoFetcher(client: client)
        let cfg = WorkspaceRepoConfig(orgs: ["octo"])
        let result = try await fetcher.run(config: cfg, ghUser: "alice")

        #expect(await client.discoverCalls == 1)
        #expect(result.fetchedRepos == ["octo/a", "octo/b"])
        #expect(result.incoming.count == 2)
    }

    @Test func excludeReposSubtractsFromTargets() async throws {
        let client = FakeRepoClient()
        let json = minimalRepoJSON(issueNumber: 1, repoFull: "octo/keep")
        await client.setFetch("octo/keep", .success(try decodeRepoQueryData(json)))
        // octo/skip not configured → would default to empty payload, but it
        // must be filtered out before fetch is even attempted.

        let fetcher = RepoFetcher(client: client)
        let cfg = WorkspaceRepoConfig(
            repos: ["octo/keep", "octo/skip"],
            excludeRepos: ["octo/skip"]
        )
        let result = try await fetcher.run(config: cfg, ghUser: "alice")

        let calls = await client.fetchCalls.sorted()
        #expect(calls == ["octo/keep"], "excludeRepos must filter pre-fetch")
        #expect(result.fetchedRepos == ["octo/keep"])
    }

    @Test func archivedRepoIsExcludedFromFetchedRepos() async throws {
        // Spec §3.D: archived/empty repos must NOT enter `fetchedRepos`,
        // protecting their existing rows from the partial-fetch close guard.
        let client = FakeRepoClient()
        await client.setFetch("octo/dead", .success(try decodeRepoQueryData(archivedRepoJSON)))
        let fetcher = RepoFetcher(client: client)
        let cfg = WorkspaceRepoConfig(repos: ["octo/dead"])

        let result = try await fetcher.run(config: cfg, ghUser: "alice")

        #expect(result.incoming.isEmpty)
        #expect(result.fetchedRepos.isEmpty,
                "archived repos must NOT be marked as fetched")
    }

    @Test func nullRepositoryPayloadIsExcludedFromFetchedRepos() async throws {
        // Empty/null repository payload: same treatment as archived. The
        // FakeRepoClient default returns repository: nil for unconfigured
        // entries, so we just leave one unset.
        let client = FakeRepoClient()
        let fetcher = RepoFetcher(client: client)
        let cfg = WorkspaceRepoConfig(repos: ["octo/missing"])

        let result = try await fetcher.run(config: cfg, ghUser: "alice")

        #expect(result.incoming.isEmpty)
        #expect(result.fetchedRepos.isEmpty)
    }

    @Test func failedRepoIsIsolatedFromTheRestOfTheCycle() async throws {
        // Per-repo fault tolerance (spec §3.D / §7): one repo throwing must
        // not abort the cycle; that repo must NOT appear in fetchedRepos
        // (so the partial-fetch guard protects its rows).
        let client = FakeRepoClient()
        await client.setFetch("octo/ok", .success(try decodeRepoQueryData(minimalRepoJSON(issueNumber: 1, repoFull: "octo/ok"))))
        await client.setFetch("octo/boom", .failure(DummyError()))

        let fetcher = RepoFetcher(client: client)
        let cfg = WorkspaceRepoConfig(repos: ["octo/ok", "octo/boom"])
        let result = try await fetcher.run(config: cfg, ghUser: "alice")

        #expect(result.fetchedRepos == ["octo/ok"])
        #expect(result.incoming.count == 1)
        // Both repos were attempted.
        let calls = Set(await client.fetchCalls)
        #expect(calls == ["octo/ok", "octo/boom"])
    }

    @Test func partialErrorsAreSurfacedPerRepo() async throws {
        let client = FakeRepoClient()
        let err = GHGraphQLError(
            message: "Field 'foo' doesn't exist",
            type: nil, path: nil
        )
        await client.setFetch(
            "octo/repo",
            .success(try decodeRepoQueryData(minimalRepoJSON(issueNumber: 1, repoFull: "octo/repo")),
                     partialErrors: [err])
        )
        let fetcher = RepoFetcher(client: client)
        let result = try await fetcher.run(
            config: WorkspaceRepoConfig(repos: ["octo/repo"]),
            ghUser: "alice"
        )

        #expect(result.partialErrors["octo/repo"]?.count == 1)
        #expect(result.partialErrors["octo/repo"]?.first?.message == "Field 'foo' doesn't exist")
        // Even with partial errors, the row was returned and the repo
        // counts as fetched (Python parity).
        #expect(result.fetchedRepos == ["octo/repo"])
    }

    @Test func malformedRepoEntryIsSkippedNotFatal() async throws {
        let client = FakeRepoClient()
        await client.setFetch("octo/ok", .success(try decodeRepoQueryData(minimalRepoJSON(issueNumber: 1, repoFull: "octo/ok"))))
        let fetcher = RepoFetcher(client: client)
        // Missing slash: malformed.
        let cfg = WorkspaceRepoConfig(repos: ["just-a-name", "octo/ok"])

        let result = try await fetcher.run(config: cfg, ghUser: "alice")

        #expect(result.fetchedRepos == ["octo/ok"])
        // The malformed entry never reached fetchRepoData.
        #expect(await client.fetchCalls == ["octo/ok"])
    }

    @Test func dedupesRepeatedRepoEntries() async throws {
        let client = FakeRepoClient()
        await client.setFetch("octo/a", .success(try decodeRepoQueryData(minimalRepoJSON(issueNumber: 1, repoFull: "octo/a"))))
        let fetcher = RepoFetcher(client: client)
        let cfg = WorkspaceRepoConfig(repos: ["octo/a", "octo/a", "octo/a"])

        _ = try await fetcher.run(config: cfg, ghUser: "alice")

        #expect(await client.fetchCalls == ["octo/a"], "duplicate repo entries collapse to one fetch")
    }

    @Test func semaphoreCapsConcurrentFetches() async throws {
        // 20 repos, cap = 4 → maxConcurrent observed by the fake should be ≤ 4.
        let client = FakeRepoClient()
        var repos: [String] = []
        for i in 0..<20 {
            let name = "octo/r\(i)"
            repos.append(name)
            await client.setFetch(name, .success(try decodeRepoQueryData(minimalRepoJSON(issueNumber: i, repoFull: name))))
        }
        let fetcher = RepoFetcher(client: client, maxConcurrent: 4)
        let result = try await fetcher.run(
            config: WorkspaceRepoConfig(repos: repos),
            ghUser: "alice"
        )

        #expect(result.fetchedRepos.count == 20)
        let observed = await client.maxConcurrent
        #expect(observed <= 4, "AsyncSemaphore cap exceeded: observed=\(observed)")
        #expect(observed > 0)
    }
}
