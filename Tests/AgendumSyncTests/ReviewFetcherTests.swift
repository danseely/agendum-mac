import Foundation
import Testing
import AgendumGitHub
@testable import AgendumSync

private actor FakeReviewClient: ReviewFetchClient {
    enum DiscoveryOutcome {
        case success([GHSearchItem], ok: Bool)
        case failure(Error)
    }

    enum DetailOutcome {
        case success(GHReviewQueryData, partialErrors: [GHGraphQLError] = [])
        case failure(Error)
    }

    var discovery: DiscoveryOutcome = .success([], ok: true)
    var details: [String: DetailOutcome] = [:]
    private(set) var discoverCalls: [([String], String)] = []
    private(set) var fetchCalls: [String] = []

    func setDiscovery(_ prs: [GHSearchItem], ok: Bool = true) {
        discovery = .success(prs, ok: ok)
    }

    func setDiscoveryFailure(_ error: Error) {
        discovery = .failure(error)
    }

    func setDetail(repo: String, number: Int, _ outcome: DetailOutcome) {
        details["\(repo)#\(number)"] = outcome
    }

    func discoverReviewPRs(orgs: [String], user: String) async throws -> (prs: [GHSearchItem], ok: Bool) {
        discoverCalls.append((orgs, user))
        switch discovery {
        case .success(let prs, let ok):
            return (prs, ok)
        case .failure(let error):
            throw error
        }
    }

    func fetchReviewDetail(owner: String, name: String, number: Int) async throws
        -> (data: GHReviewQueryData, partialErrors: [GHGraphQLError])
    {
        let key = "\(owner)/\(name)#\(number)"
        fetchCalls.append(key)
        guard let outcome = details[key] else {
            return (try decodeReviewData(reviewDetailJSON(repo: "\(owner)/\(name)", number: number)), [])
        }
        switch outcome {
        case .success(let data, let partialErrors):
            return (data, partialErrors)
        case .failure(let error):
            throw error
        }
    }
}

private struct DummyError: Error {}

@Suite struct ReviewFetcherTests {
    @Test
    func happyPathMapsDiscoveredPRsIntoReviewTasks() async throws {
        let client = FakeReviewClient()
        let pr = searchItem(repo: "acme/widget", number: 42, title: "Review me")
        await client.setDiscovery([pr])

        let result = await fetchReviewTasks(
            config: WorkspaceRepoConfig(orgs: ["acme"]),
            user: "danseely",
            client: client
        )

        #expect(result.reviewFetchOK)
        #expect(result.incoming.count == 1)
        let task = try #require(result.incoming.first)
        #expect(task.source == "pr_review")
        #expect(task.status == "review requested")
        #expect(task.title == "Review me")
        #expect(task.ghURL == "https://github.com/acme/widget/pull/42")
        #expect(task.ghRepo == "acme/widget")
        #expect(task.project == "widget")
        #expect(task.tags == #"["review"]"#)
        #expect(await client.fetchCalls == ["acme/widget#42"])
    }

    @Test
    func excludeRepoFilterPreventsDetailFetch() async throws {
        let client = FakeReviewClient()
        await client.setDiscovery([
            searchItem(repo: "acme/keep", number: 1),
            searchItem(repo: "acme/skip", number: 2),
        ])

        let result = await fetchReviewTasks(
            config: WorkspaceRepoConfig(orgs: ["acme"], excludeRepos: ["acme/skip"]),
            user: "danseely",
            client: client
        )

        #expect(result.reviewFetchOK)
        #expect(result.incoming.map(\.ghRepo) == ["acme/keep"])
        #expect(await client.fetchCalls == ["acme/keep#1"])
    }

    @Test
    func repoAllowListPreventsDetailFetchOutsideConfiguredRepos() async throws {
        let client = FakeReviewClient()
        await client.setDiscovery([
            searchItem(repo: "acme/keep", number: 1),
            searchItem(repo: "acme/outside", number: 2),
        ])

        let result = await fetchReviewTasks(
            config: WorkspaceRepoConfig(repos: ["acme/keep"], orgs: ["acme"]),
            user: "danseely",
            client: client
        )

        #expect(result.reviewFetchOK)
        #expect(result.incoming.map(\.ghRepo) == ["acme/keep"])
        #expect(await client.fetchCalls == ["acme/keep#1"])
    }

    @Test
    func apiURLFallbackDerivesRepoFullNameWhenRepositoryLacksOwner() async throws {
        let client = FakeReviewClient()
        await client.setDiscovery([
            GHSearchItem(
                number: 5,
                title: "API URL",
                url: "https://api.github.com/repos/acme/widget/issues/5",
                repository: GHSearchRepository(name: "widget"),
                author: nil
            )
        ])

        let result = await fetchReviewTasks(
            config: WorkspaceRepoConfig(orgs: ["acme"]),
            user: "danseely",
            client: client
        )

        #expect(result.reviewFetchOK)
        #expect(result.incoming.map(\.ghRepo) == ["acme/widget"])
        #expect(await client.fetchCalls == ["acme/widget#5"])
    }

    @Test
    func repoOnlyWorkspaceReturnsReviewFetchNotOK() async throws {
        let client = FakeReviewClient()

        let result = await fetchReviewTasks(
            config: WorkspaceRepoConfig(repos: ["acme/widget"]),
            user: "danseely",
            client: client
        )

        #expect(result.incoming.isEmpty)
        #expect(result.reviewFetchOK == false)
        #expect(await client.discoverCalls.isEmpty)
        #expect(await client.fetchCalls.isEmpty)
    }

    @Test
    func emptyWorkspaceReturnsReviewFetchNotOKDefensively() async throws {
        let client = FakeReviewClient()

        let result = await fetchReviewTasks(
            config: WorkspaceRepoConfig(),
            user: "danseely",
            client: client
        )

        #expect(result.incoming.isEmpty)
        #expect(result.reviewFetchOK == false)
        #expect(await client.discoverCalls.isEmpty)
        #expect(await client.fetchCalls.isEmpty)
    }

    @Test
    func discoveryIncompletePropagatesReviewFetchNotOK() async throws {
        let client = FakeReviewClient()
        await client.setDiscovery([searchItem(repo: "acme/widget", number: 7)], ok: false)

        let result = await fetchReviewTasks(
            config: WorkspaceRepoConfig(orgs: ["acme", "flaky"]),
            user: "danseely",
            client: client
        )

        #expect(result.reviewFetchOK == false)
        #expect(result.incoming.count == 1, "partial discovery results still map")
        #expect(await client.fetchCalls == ["acme/widget#7"])
    }

    @Test
    func discoveryFailureReturnsReviewFetchNotOK() async throws {
        let client = FakeReviewClient()
        await client.setDiscoveryFailure(DummyError())

        let result = await fetchReviewTasks(
            config: WorkspaceRepoConfig(orgs: ["acme"]),
            user: "danseely",
            client: client
        )

        #expect(result.incoming.isEmpty)
        #expect(result.reviewFetchOK == false)
        #expect(await client.fetchCalls.isEmpty)
    }

    @Test
    func nilOrUnmappableReviewDetailIsSkipped() async throws {
        let client = FakeReviewClient()
        await client.setDiscovery([
            searchItem(repo: "acme/ok", number: 1),
            searchItem(repo: "acme/missing", number: 2),
        ])
        await client.setDetail(
            repo: "acme/missing",
            number: 2,
            .success(try decodeReviewData(#"{"data":{"repository":{"pullRequest":null}}}"#))
        )

        let result = await fetchReviewTasks(
            config: WorkspaceRepoConfig(orgs: ["acme"]),
            user: "danseely",
            client: client
        )

        #expect(result.reviewFetchOK)
        #expect(result.incoming.map(\.ghRepo) == ["acme/ok"])
        #expect(await client.fetchCalls == ["acme/ok#1", "acme/missing#2"])
    }

    @Test
    func perPRDetailFailureSkipsThatPR() async throws {
        let client = FakeReviewClient()
        await client.setDiscovery([
            searchItem(repo: "acme/ok", number: 1),
            searchItem(repo: "acme/boom", number: 2),
        ])
        await client.setDetail(repo: "acme/boom", number: 2, .failure(DummyError()))

        let result = await fetchReviewTasks(
            config: WorkspaceRepoConfig(orgs: ["acme"]),
            user: "danseely",
            client: client
        )

        #expect(result.reviewFetchOK)
        #expect(result.incoming.map(\.ghRepo) == ["acme/ok"])
        #expect(await client.fetchCalls == ["acme/ok#1", "acme/boom#2"])
    }

    @Test
    func serialDetailFetchOrderIsStable() async throws {
        let client = FakeReviewClient()
        await client.setDiscovery([
            searchItem(repo: "acme/one", number: 1),
            searchItem(repo: "acme/two", number: 2),
            searchItem(repo: "acme/three", number: 3),
        ])

        let result = await fetchReviewTasks(
            config: WorkspaceRepoConfig(orgs: ["acme"]),
            user: "danseely",
            client: client
        )

        #expect(result.incoming.map(\.ghRepo) == ["acme/one", "acme/two", "acme/three"])
        #expect(await client.fetchCalls == ["acme/one#1", "acme/two#2", "acme/three#3"])
    }
}

private func searchItem(repo: String, number: Int, title: String = "T") -> GHSearchItem {
    let shortName = repo.split(separator: "/", maxSplits: 1).last.map(String.init)
    return GHSearchItem(
        number: number,
        title: title,
        url: "https://github.com/\(repo)/pull/\(number)",
        repository: GHSearchRepository(nameWithOwner: repo, name: shortName),
        author: GHAuthor(login: "octocat", name: "Octo Cat")
    )
}

private func decodeReviewData(_ json: String) throws -> GHReviewQueryData {
    let envelope = try JSONDecoder().decode(GHGraphQLResponse<GHReviewQueryData>.self, from: Data(json.utf8))
    guard let data = envelope.data else {
        throw DummyError()
    }
    return data
}

private func reviewDetailJSON(repo: String, number: Int) -> String {
    #"""
    {
      "data": {
        "repository": {
          "pullRequest": {
            "number": \#(number),
            "title": "Review me",
            "url": "https://github.com/\#(repo)/pull/\#(number)",
            "state": "OPEN",
            "createdAt": "2026-05-01T00:00:00Z",
            "isDraft": false,
            "headRefName": "main",
            "author": {"login": "octocat", "name": "Octo Cat"},
            "commits": {"nodes": [{"commit": {"committedDate": "2026-05-09T07:00:00Z"}}]},
            "reviews": {"nodes": []},
            "timelineItems": {"nodes": []}
          }
        }
      }
    }
    """#
}
