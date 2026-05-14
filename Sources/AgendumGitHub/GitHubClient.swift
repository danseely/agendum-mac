import Foundation

/// Public errors surfaced by `GitHubClient`. Distinguishes transport,
/// HTTP, auth, rate-limit, decoding, and GraphQL-level failures so
/// callers (and tests) can branch by reason.
public enum GitHubClientError: Error, Sendable, CustomStringConvertible {
    case transportFailed(any Error)
    case httpStatus(code: Int, body: String?)
    case unauthorized
    case rateLimited(resetAt: Date?)
    case decodingFailed(any Error)
    case graphQLErrors([GHGraphQLError])
    case missingData
    case authFailed(GitHubAuthError)

    public var description: String {
        switch self {
        case .transportFailed(let e):
            return "GitHub transport error: \(e.localizedDescription)"
        case .httpStatus(let code, let body):
            let suffix = body.flatMap { $0.isEmpty ? nil : ": \($0)" } ?? ""
            return "GitHub HTTP \(code)\(suffix)"
        case .unauthorized:
            return "GitHub returned 401. Token may be expired or missing scopes. Run `gh auth login`."
        case .rateLimited(let resetAt):
            if let resetAt {
                return "GitHub rate limit exhausted. Resets at \(resetAt)."
            }
            return "GitHub rate limit exhausted."
        case .decodingFailed(let e):
            return "Failed to decode GitHub response: \(e)"
        case .graphQLErrors(let errors):
            return "GitHub GraphQL errors: \(errors.map(\.description).joined(separator: "; "))"
        case .missingData:
            return "GitHub response was missing the expected data."
        case .authFailed(let e):
            return e.description
        }
    }
}

/// Pure HTTP client for the GitHub API. Holds a URLSession + a bearer-token
/// provider; produces decoded response types (see `Responses.swift`) for the
/// two GraphQL queries and the small REST surface the sync engine needs.
///
/// **Scope**: this layer is transport-only — no diffing, no DB writes, no UI
/// concepts. The sync engine (S3) imports this module to drive sync; the UI
/// imports it for nothing.
public actor GitHubClient {
    public typealias Session = URLSession

    private let session: Session
    private let tokenProvider: any GitHubTokenProviding
    private let baseURL: URL
    private let decoder: JSONDecoder

    /// Maximum concurrent in-flight requests. Mirrors Python `Semaphore(8)` in
    /// `syncer._run_sync_once`; tunable via initializer for tests / power users
    /// with very-many-repo workspaces.
    public let concurrencyLimit: Int

    public init(
        baseURL: URL = URL(string: "https://api.github.com")!,
        session: Session = .shared,
        tokenProvider: any GitHubTokenProviding = GhCLITokenProvider(),
        concurrencyLimit: Int = 8
    ) {
        self.baseURL = baseURL
        self.session = session
        self.tokenProvider = tokenProvider
        self.concurrencyLimit = concurrencyLimit
        self.decoder = JSONDecoder()
    }

    // MARK: - REST: /user

    /// `GET /user` → `.login`. Maps to Python `gh.get_gh_username`.
    public func currentUserLogin() async throws -> String {
        let user: GHUserResponse = try await getJSON("/user")
        return user.login
    }

    // MARK: - GraphQL: REPO_QUERY

    /// Fetches the per-repo bundle (authored PRs + assigned issues + recent
    /// terminal PRs/issues) for `owner/name` filtered by `user`.
    /// Mirrors Python `gh.fetch_repo_data`.
    /// Returns `(data, partialErrors)` so callers can surface partial-success
    /// warnings if any.
    public func fetchRepoData(owner: String, name: String, user: String) async throws -> (data: GHRepoQueryData, partialErrors: [GHGraphQLError]) {
        try await graphQL(
            query: GraphQLQueries.repo,
            variables: [
                "owner": .string(owner),
                "name": .string(name),
                "user": .string(user),
            ],
            as: GHRepoQueryData.self
        )
    }

    // MARK: - GraphQL: REVIEW_QUERY

    /// Fetches per-PR review detail for the review-requested path.
    /// Mirrors Python `gh.fetch_review_detail`.
    public func fetchReviewDetail(owner: String, name: String, number: Int) async throws -> (data: GHReviewQueryData, partialErrors: [GHGraphQLError]) {
        try await graphQL(
            query: GraphQLQueries.review,
            variables: [
                "owner": .string(owner),
                "name": .string(name),
                "number": .int(number),
            ],
            as: GHReviewQueryData.self
        )
    }

    // MARK: - REST search: repo discovery + review-requested PR discovery

    /// `discover_repos(orgs, user)`: across each org, run three search queries
    /// (author / assignee / review-requested) and union the repos that surface.
    /// Mirrors Python `gh.discover_repos`. Returns the union as a sorted array
    /// for stable iteration.
    public func discoverRepos(orgs: [String], user: String) async throws -> [String] {
        var seen: Set<String> = []
        for org in orgs {
            let queries = [
                "is:pr is:open author:\(user) org:\(org)",
                "is:issue is:open assignee:\(user) org:\(org)",
                "is:pr is:open review-requested:\(user) org:\(org)",
            ]
            for q in queries {
                let items = try await searchIssues(q: q, limit: 200)
                for item in items {
                    if let name = item.repository?.nameWithOwner, !name.isEmpty {
                        seen.insert(name)
                    } else if let name = item.repository?.name, !name.isEmpty {
                        seen.insert(name)
                    }
                }
            }
        }
        return seen.sorted()
    }

    /// `discover_review_prs(orgs, user)`: across each org, find PRs where the
    /// user's review is requested. Returns `(prs, ok)` where `ok == false` if
    /// any org's search **failed** (transport / HTTP error caught), matching
    /// Python's `gh.discover_review_prs` semantics. Empty results from a
    /// successful search keep `ok == true` — an org with no pending reviews
    /// is normal and must not suppress `pr_review` row closure downstream.
    public func discoverReviewPRs(orgs: [String], user: String) async throws -> (prs: [GHSearchItem], ok: Bool) {
        var collected: [GHSearchItem] = []
        var ok = true
        for org in orgs {
            let q = "is:pr is:open review-requested:\(user) org:\(org)"
            do {
                let items = try await searchIssues(q: q, limit: 200)
                collected.append(contentsOf: items)
            } catch let err as GitHubClientError {
                logger.warning("discoverReviewPRs failed for org \(org, privacy: .public): \(String(describing: err), privacy: .public)")
                ok = false
            }
        }
        return (collected, ok)
    }

    // MARK: - Internal: HTTP helpers

    /// Runs a GraphQL POST against `/graphql` and decodes either:
    ///   - successful `{ data: T }` → returns `(T, partialErrors)`
    ///   - `{ errors: […] }` → throws `.graphQLErrors`
    ///   - `{ data: null, errors: […] }` → throws `.graphQLErrors`
    ///   - missing `data` and no errors → throws `.missingData`
    ///
    /// On partial success (`data` present + non-empty `errors`), returns both
    /// so callers can decide whether to surface the warnings.
    private func graphQL<T: Decodable & Sendable>(
        query: String,
        variables: [String: GraphQLVariable],
        as type: T.Type
    ) async throws -> (data: T, partialErrors: [GHGraphQLError]) {
        let body = GraphQLRequestBody(query: query, variables: variables)
        let data: Data = try await postJSON("/graphql", body: body)
        let envelope: GHGraphQLResponse<T>
        do {
            envelope = try decoder.decode(GHGraphQLResponse<T>.self, from: data)
        } catch {
            throw GitHubClientError.decodingFailed(error)
        }
        if let errors = envelope.errors, !errors.isEmpty, envelope.data == nil {
            throw GitHubClientError.graphQLErrors(errors)
        }
        if let data = envelope.data {
            let partial = envelope.errors ?? []
            if !partial.isEmpty {
                logger.warning(
                    "GraphQL partial success with \(partial.count, privacy: .public) error(s): \(partial.map(\.description).joined(separator: "; "), privacy: .public)"
                )
            }
            return (data, partial)
        }
        throw GitHubClientError.missingData
    }

    /// Paginates GitHub's REST `/search/issues` endpoint up to `limit` items
    /// (matches Python's `gh search … --limit 200` behavior). Per-page is
    /// capped at GitHub's max of 100; we paginate as needed.
    private func searchIssues(q: String, limit: Int) async throws -> [GHSearchItem] {
        struct Page: Decodable {
            let totalCount: Int
            let items: [GHSearchItem]
            enum CodingKeys: String, CodingKey {
                case totalCount = "total_count"
                case items
            }
        }
        var collected: [GHSearchItem] = []
        let perPage = min(100, limit)
        var page = 1
        while collected.count < limit {
            var components = URLComponents(url: baseURL.appendingPathComponent("/search/issues"), resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "q", value: q),
                URLQueryItem(name: "per_page", value: String(perPage)),
                URLQueryItem(name: "page", value: String(page)),
            ]
            guard let url = components.url else { break }
            let data = try await getData(url: url)
            let pageResult: Page
            do {
                pageResult = try decoder.decode(Page.self, from: data)
            } catch {
                throw GitHubClientError.decodingFailed(error)
            }
            if pageResult.items.isEmpty { break }
            collected.append(contentsOf: pageResult.items)
            if collected.count >= pageResult.totalCount { break }
            page += 1
            if page > 10 { break } // GitHub caps search at 1000 results (10 pages × 100)
        }
        if collected.count > limit {
            collected = Array(collected.prefix(limit))
        }
        return collected
    }

    private func getJSON<T: Decodable & Sendable>(_ path: String) async throws -> T {
        let url = baseURL.appendingPathComponent(path)
        let data = try await getData(url: url)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw GitHubClientError.decodingFailed(error)
        }
    }

    private func getData(url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("agendum-mac/0.1 (Swift)", forHTTPHeaderField: "User-Agent")
        return try await runWithAuthRetry(request)
    }

    private func postJSON<Body: Encodable>(_ path: String, body: Body) async throws -> Data {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("agendum-mac/0.1 (Swift)", forHTTPHeaderField: "User-Agent")
        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw GitHubClientError.decodingFailed(error)
        }
        return try await runWithAuthRetry(request)
    }

    private func applyAuth(_ request: inout URLRequest) async throws {
        do {
            let token = try await tokenProvider.token()
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } catch let authError as GitHubAuthError {
            throw GitHubClientError.authFailed(authError)
        } catch {
            throw GitHubClientError.authFailed(.ghCLIFailed(stderr: String(describing: error), exitCode: -1))
        }
    }

    /// Runs the request; on 401, invalidates the cached token and retries once.
    private func runWithAuthRetry(_ originalRequest: URLRequest) async throws -> Data {
        for attempt in 0..<2 {
            var request = originalRequest
            try await applyAuth(&request)
            let result: (Data, URLResponse)
            do {
                result = try await session.data(for: request)
            } catch {
                throw GitHubClientError.transportFailed(error)
            }
            let (data, response) = result
            guard let http = response as? HTTPURLResponse else {
                throw GitHubClientError.transportFailed(URLError(.badServerResponse))
            }
            switch http.statusCode {
            case 200..<300:
                return data
            case 401:
                if attempt == 0 {
                    await tokenProvider.invalidate()
                    continue
                }
                throw GitHubClientError.unauthorized
            case 403, 429:
                // Primary rate limit: `x-ratelimit-remaining: 0` + `x-ratelimit-reset` epoch.
                // Secondary / abuse rate limit + 429: `Retry-After` header (seconds).
                if let retry = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init) {
                    throw GitHubClientError.rateLimited(resetAt: Date(timeIntervalSinceNow: retry))
                }
                if http.value(forHTTPHeaderField: "x-ratelimit-remaining") == "0" {
                    let reset = http.value(forHTTPHeaderField: "x-ratelimit-reset")
                        .flatMap { TimeInterval($0) }
                        .map { Date(timeIntervalSince1970: $0) }
                    throw GitHubClientError.rateLimited(resetAt: reset)
                }
                if http.statusCode == 429 {
                    throw GitHubClientError.rateLimited(resetAt: nil)
                }
                fallthrough
            default:
                let body = String(data: data, encoding: .utf8)
                throw GitHubClientError.httpStatus(code: http.statusCode, body: body)
            }
        }
        // Unreachable — loop returns or throws.
        throw GitHubClientError.unauthorized
    }
}

private struct GraphQLRequestBody: Encodable {
    let query: String
    let variables: [String: GraphQLVariable]
}

/// Typed GraphQL variable. Strict, no bridging-quirks (e.g. `Bool` decoded as
/// `Int` after `NSNumber` round-trip). The two queries the client ships today
/// only need `String` and `Int`; the other cases are present for forward
/// compatibility without resorting to `Any` encoding.
public enum GraphQLVariable: Encodable, Sendable, Equatable {
    case string(String)
    case int(Int)
    case bool(Bool)
    case double(Double)
    case null
    indirect case array([GraphQLVariable])
    indirect case object([String: GraphQLVariable])

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .int(let i): try container.encode(i)
        case .bool(let b): try container.encode(b)
        case .double(let d): try container.encode(d)
        case .null: try container.encodeNil()
        case .array(let arr): try container.encode(arr)
        case .object(let obj): try container.encode(obj)
        }
    }
}
