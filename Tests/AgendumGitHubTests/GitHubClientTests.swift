@testable import AgendumGitHub
import Foundation
import Testing

/// In-memory token provider for tests.
actor FakeTokenProvider: GitHubTokenProviding {
    private var value: String
    private(set) var invalidations: Int = 0

    init(initial: String) { self.value = initial }

    func setToken(_ new: String) { value = new }
    func token() async throws -> String { value }
    func invalidate() async { invalidations += 1 }
}

@Suite("GitHubClient — HTTP transport", .serialized)
struct GitHubClientTests {

    // MARK: - REST: /user

    @Test
    func currentUserLoginParsesLogin() async throws {
        let body = try fixtureData("userResponse")
        StubURLProtocol.setHandler { _ in (200, ["Content-Type": "application/json"], body) }
        defer { StubURLProtocol.setHandler(nil) }

        let client = GitHubClient(
            session: StubURLProtocol.makeSession(),
            tokenProvider: FakeTokenProvider(initial: "tok")
        )

        let login = try await client.currentUserLogin()
        #expect(login == "danseely")
    }

    @Test
    func authHeaderIsBearerFromProvider() async throws {
        let recorded = RecordedRequests()
        let body = try fixtureData("userResponse")
        StubURLProtocol.setHandler { req in
            recorded.append(req)
            return (200, ["Content-Type": "application/json"], body)
        }
        defer { StubURLProtocol.setHandler(nil) }

        let client = GitHubClient(
            session: StubURLProtocol.makeSession(),
            tokenProvider: FakeTokenProvider(initial: "secret-token")
        )
        _ = try await client.currentUserLogin()

        #expect(recorded.count == 1)
        #expect(recorded.all.first?.value(forHTTPHeaderField: "Authorization") == "Bearer secret-token")
        #expect(recorded.all.first?.value(forHTTPHeaderField: "Accept") == "application/vnd.github+json")
    }

    @Test
    func unauthorizedTriggersTokenInvalidationAndOneRetry() async throws {
        let body = try fixtureData("userResponse")
        let provider = FakeTokenProvider(initial: "stale")
        let calls = RecordedRequests()
        // First call → 401; second call → 200.
        StubURLProtocol.setHandler { req in
            calls.append(req)
            if calls.count == 1 {
                return (401, [:], Data("bad creds".utf8))
            }
            return (200, ["Content-Type": "application/json"], body)
        }
        defer { StubURLProtocol.setHandler(nil) }

        let client = GitHubClient(
            session: StubURLProtocol.makeSession(),
            tokenProvider: provider
        )
        let login = try await client.currentUserLogin()
        #expect(login == "danseely")
        #expect(calls.count == 2)
        #expect(await provider.invalidations == 1)
    }

    @Test
    func unauthorizedOnRetrySurfacesAsUnauthorized() async throws {
        let calls = RecordedRequests()
        StubURLProtocol.setHandler { req in
            calls.append(req)
            return (401, [:], Data("bad creds".utf8))
        }
        defer { StubURLProtocol.setHandler(nil) }

        let client = GitHubClient(
            session: StubURLProtocol.makeSession(),
            tokenProvider: FakeTokenProvider(initial: "stale")
        )

        do {
            _ = try await client.currentUserLogin()
            Issue.record("expected unauthorized")
        } catch GitHubClientError.unauthorized {
            // expected
        }
        #expect(calls.count == 2)
    }

    @Test
    func rateLimitedSurfacesResetAt() async throws {
        StubURLProtocol.setHandler { _ in
            (
                403,
                [
                    "x-ratelimit-remaining": "0",
                    "x-ratelimit-reset": "2000000000",
                ],
                Data()
            )
        }
        defer { StubURLProtocol.setHandler(nil) }

        let client = GitHubClient(
            session: StubURLProtocol.makeSession(),
            tokenProvider: FakeTokenProvider(initial: "t")
        )

        do {
            _ = try await client.currentUserLogin()
            Issue.record("expected rateLimited")
        } catch GitHubClientError.rateLimited(let resetAt) {
            let expected = Date(timeIntervalSince1970: 2_000_000_000)
            #expect(resetAt == expected)
        }
    }

    // MARK: - GraphQL: REPO_QUERY

    @Test
    func fetchRepoDataDecodesHappyPathFixture() async throws {
        let body = try fixtureData("repoQueryHappyPath")
        StubURLProtocol.setHandler { _ in (200, ["Content-Type": "application/json"], body) }
        defer { StubURLProtocol.setHandler(nil) }

        let client = GitHubClient(
            session: StubURLProtocol.makeSession(),
            tokenProvider: FakeTokenProvider(initial: "t")
        )
        let data = try await client.fetchRepoData(owner: "acme", name: "widget", user: "danseely")
        let repo = try #require(data.repository)

        #expect(repo.isArchived == false)
        #expect(repo.openIssues?.nodes.count == 1)
        #expect(repo.openIssues?.nodes.first?.title == "Bug: nav drawer flickers")
        #expect(repo.openIssues?.nodes.first?.labels?.nodes.map(\.name) == ["bug", "ui"])
        #expect(repo.openIssues?.nodes.first?.timelineItems?.nodes.first?.subject?.url == "https://github.com/acme/widget/pull/99")

        #expect(repo.authoredPRs?.nodes.count == 1)
        let pr = try #require(repo.authoredPRs?.nodes.first)
        #expect(pr.number == 99)
        #expect(pr.title == "Fix nav drawer flicker")
        #expect(pr.author?.login == "danseely")
        #expect(pr.reviewRequests?.totalCount == 2)
        #expect(pr.commits?.nodes.first?.commit?.committedDate == "2026-05-06T09:30:00Z")
        #expect(pr.reviews?.nodes.first?.id == "REVIEW_1")
        #expect(pr.reviewThreads?.nodes.first?.isResolved == false)
        #expect(pr.labels?.nodes.map(\.name) == ["frontend"])

        #expect(repo.mergedPRs?.nodes.first?.number == 88)
        #expect(repo.closedPRs?.nodes.first?.number == 77)
        #expect(repo.closedIssues?.nodes.first?.number == 30)
    }

    @Test
    func fetchRepoDataPostsGraphQLBodyWithVariables() async throws {
        let recorded = RecordedRequests()
        let bodyData = try fixtureData("repoQueryHappyPath")
        StubURLProtocol.setHandler { req in
            recorded.append(req)
            return (200, ["Content-Type": "application/json"], bodyData)
        }
        defer { StubURLProtocol.setHandler(nil) }

        let client = GitHubClient(
            session: StubURLProtocol.makeSession(),
            tokenProvider: FakeTokenProvider(initial: "t")
        )
        _ = try await client.fetchRepoData(owner: "acme", name: "widget", user: "danseely")

        let request = try #require(recorded.all.first)
        #expect(request.url?.path == "/graphql")
        #expect(request.httpMethod == "POST")
        // URLSession with stub protocol moves httpBody into httpBodyStream — handle both.
        let sent: Data
        if let direct = request.httpBody {
            sent = direct
        } else if let stream = request.httpBodyStream {
            sent = try Data(readingFrom: stream)
        } else {
            Issue.record("expected request body")
            return
        }
        let parsed = try #require(try JSONSerialization.jsonObject(with: sent) as? [String: Any])
        let variables = try #require(parsed["variables"] as? [String: Any])
        #expect((variables["owner"] as? String) == "acme")
        #expect((variables["name"] as? String) == "widget")
        #expect((variables["user"] as? String) == "danseely")
        #expect((parsed["query"] as? String)?.contains("query($owner: String!") == true)
    }

    @Test
    func graphQLErrorsArrayThrowsGraphQLErrors() async throws {
        let body = try fixtureData("graphQLErrors")
        StubURLProtocol.setHandler { _ in (200, ["Content-Type": "application/json"], body) }
        defer { StubURLProtocol.setHandler(nil) }

        let client = GitHubClient(
            session: StubURLProtocol.makeSession(),
            tokenProvider: FakeTokenProvider(initial: "t")
        )

        do {
            _ = try await client.fetchRepoData(owner: "acme", name: "missing", user: "danseely")
            Issue.record("expected graphQLErrors")
        } catch GitHubClientError.graphQLErrors(let errors) {
            #expect(errors.count == 1)
            #expect(errors[0].message.contains("Could not resolve"))
            #expect(errors[0].type == "NOT_FOUND")
        }
    }

    // MARK: - GraphQL: REVIEW_QUERY

    @Test
    func fetchReviewDetailDecodesHappyPathFixture() async throws {
        let body = try fixtureData("reviewQueryHappyPath")
        StubURLProtocol.setHandler { _ in (200, ["Content-Type": "application/json"], body) }
        defer { StubURLProtocol.setHandler(nil) }

        let client = GitHubClient(
            session: StubURLProtocol.makeSession(),
            tokenProvider: FakeTokenProvider(initial: "t")
        )
        let data = try await client.fetchReviewDetail(owner: "acme", name: "widget", number: 1234)
        let pr = try #require(data.repository?.pullRequest)
        #expect(pr.number == 1234)
        #expect(pr.author?.login == "octocat")
        #expect(pr.author?.name == "Octo Cat")
        #expect(pr.commits?.nodes.first?.commit?.committedDate == "2026-05-09T07:00:00Z")
        #expect(pr.reviews?.nodes.first?.author?.login == "danseely")
        #expect(pr.timelineItems?.nodes.first?.requestedReviewer?.login == "danseely")
    }

    // MARK: - REST search

    @Test
    func discoverReposUnionsAcrossSearchQueries() async throws {
        let body = try fixtureData("searchPRsHappyPath")
        let recorded = RecordedRequests()
        StubURLProtocol.setHandler { req in
            recorded.append(req)
            return (200, ["Content-Type": "application/json"], body)
        }
        defer { StubURLProtocol.setHandler(nil) }

        let client = GitHubClient(
            session: StubURLProtocol.makeSession(),
            tokenProvider: FakeTokenProvider(initial: "t")
        )
        let repos = try await client.discoverRepos(orgs: ["acme"], user: "danseely")

        // Three search queries per org (author / assignee / review-requested);
        // each returns the same fixture, so the union has two repos.
        #expect(recorded.count == 3)
        #expect(repos.sorted() == ["acme/other", "acme/widget"])
    }

    @Test
    func discoverReviewPRsFlagsIncompleteWhenAnyOrgReturnsEmpty() async throws {
        let body = try fixtureData("searchPRsHappyPath")
        let emptyBody = Data(#"{"total_count":0,"incomplete_results":false,"items":[]}"#.utf8)
        let recorded = RecordedRequests()
        StubURLProtocol.setHandler { req in
            recorded.append(req)
            let url = req.url?.absoluteString ?? ""
            // The second org's search returns empty → ok=false
            if url.contains("org:other") {
                return (200, ["Content-Type": "application/json"], emptyBody)
            }
            return (200, ["Content-Type": "application/json"], body)
        }
        defer { StubURLProtocol.setHandler(nil) }

        let client = GitHubClient(
            session: StubURLProtocol.makeSession(),
            tokenProvider: FakeTokenProvider(initial: "t")
        )
        let result = try await client.discoverReviewPRs(orgs: ["acme", "other"], user: "danseely")
        #expect(result.prs.count == 2)
        #expect(result.ok == false)
    }

    // MARK: - Helpers

    private func fixtureData(_ name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json") else {
            throw FixtureError.notFound(name)
        }
        return try Data(contentsOf: url)
    }

    enum FixtureError: Error { case notFound(String) }
}

// MARK: - InputStream → Data helper

extension Data {
    init(readingFrom stream: InputStream) throws {
        stream.open()
        defer { stream.close() }
        var buffer = [UInt8](repeating: 0, count: 4096)
        var data = Data()
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read < 0 {
                throw stream.streamError ?? URLError(.cannotLoadFromNetwork)
            }
            if read == 0 { break }
            data.append(buffer, count: read)
        }
        self = data
    }
}
