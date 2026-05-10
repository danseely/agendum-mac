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
    public func fetchRepoData(owner: String, name: String, user: String) async throws -> GHRepoQueryData {
        try await graphQL(
            query: GraphQLQueries.repo,
            variables: ["owner": owner, "name": name, "user": user],
            as: GHRepoQueryData.self
        )
    }

    // MARK: - GraphQL: REVIEW_QUERY

    /// Fetches per-PR review detail for the review-requested path.
    /// Mirrors Python `gh.fetch_review_detail`.
    public func fetchReviewDetail(owner: String, name: String, number: Int) async throws -> GHReviewQueryData {
        try await graphQL(
            query: GraphQLQueries.review,
            variables: ["owner": owner, "name": name, "number": number],
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
    /// any org's search returned 0 items (treated as "may be incomplete";
    /// downstream sync uses this to suppress `pr_review` row closures).
    /// Mirrors Python `gh.discover_review_prs`.
    public func discoverReviewPRs(orgs: [String], user: String) async throws -> (prs: [GHSearchItem], ok: Bool) {
        var collected: [GHSearchItem] = []
        var ok = true
        for org in orgs {
            let q = "is:pr is:open review-requested:\(user) org:\(org)"
            let items = try await searchIssues(q: q, limit: 200)
            if items.isEmpty {
                ok = false
            }
            collected.append(contentsOf: items)
        }
        return (collected, ok)
    }

    // MARK: - Internal: HTTP helpers

    /// Runs a GraphQL POST against `/graphql` and decodes either:
    ///   - successful `{ data: T }` → returns `T`
    ///   - `{ errors: […] }` → throws `.graphQLErrors`
    ///   - `{ data: null, errors: […] }` → throws `.graphQLErrors`
    ///   - missing `data` and no errors → throws `.missingData`
    private func graphQL<T: Decodable & Sendable>(
        query: String,
        variables: [String: any Sendable],
        as type: T.Type
    ) async throws -> T {
        let body = GraphQLRequestBody(query: query, variables: AnyEncodable(variables))
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
            // Partial-success: log non-fatal errors but return the data we got.
            if let errors = envelope.errors, !errors.isEmpty {
                logger.warning("GraphQL partial success with \(errors.count, privacy: .public) error(s); proceeding with data")
            }
            return data
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
        try await applyAuth(&request)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("agendum-mac/0.1 (Swift)", forHTTPHeaderField: "User-Agent")
        return try await runWithAuthRetry(request)
    }

    private func postJSON<Body: Encodable>(_ path: String, body: Body) async throws -> Data {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        try await applyAuth(&request)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
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
            if attempt > 0 {
                // Refresh auth header
                try await applyAuth(&request)
            }
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
            case 403:
                if http.value(forHTTPHeaderField: "x-ratelimit-remaining") == "0" {
                    let reset = http.value(forHTTPHeaderField: "x-ratelimit-reset")
                        .flatMap { TimeInterval($0) }
                        .map { Date(timeIntervalSince1970: $0) }
                    throw GitHubClientError.rateLimited(resetAt: reset)
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
    let variables: AnyEncodable
}

// MARK: - JSON encoding helper

/// Encodes a `[String: Any-Sendable]` payload for GraphQL `variables`.
/// Foundation's `JSONEncoder` can't encode `Any`; this wrapper bridges via
/// `JSONSerialization` so callers can pass heterogeneous values (`String`,
/// `Int`, etc.) without per-call boilerplate.
struct AnyEncodable: Encodable {
    let value: [String: any Sendable]

    init(_ value: [String: any Sendable]) {
        self.value = value
    }

    func encode(to encoder: Encoder) throws {
        let data = try JSONSerialization.data(withJSONObject: value)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw EncodingError.invalidValue(value, EncodingError.Context(
                codingPath: encoder.codingPath,
                debugDescription: "GraphQL variables payload was not a JSON object"
            ))
        }
        var container = encoder.container(keyedBy: DynamicKey.self)
        for (key, anyValue) in object {
            let codingKey = DynamicKey(stringValue: key)!
            try encode(value: anyValue, forKey: codingKey, into: &container)
        }
    }

    private func encode(
        value: Any,
        forKey key: DynamicKey,
        into container: inout KeyedEncodingContainer<DynamicKey>
    ) throws {
        switch value {
        case let s as String: try container.encode(s, forKey: key)
        case let i as Int: try container.encode(i, forKey: key)
        case let d as Double: try container.encode(d, forKey: key)
        case let b as Bool: try container.encode(b, forKey: key)
        case is NSNull: try container.encodeNil(forKey: key)
        default:
            // Fall back to JSONSerialization round-trip for nested containers.
            let data = try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])
            let raw = String(decoding: data, as: UTF8.self)
            // Wrap raw JSON so it lands as-is in the encoded output.
            try container.encode(RawJSON(raw: raw), forKey: key)
        }
    }
}

private struct DynamicKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

private struct RawJSON: Encodable {
    let raw: String
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        // Decode the raw JSON into the nearest Codable shape so it round-trips.
        let data = Data(raw.utf8)
        if let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
            switch obj {
            case let s as String: try container.encode(s)
            case let n as NSNumber:
                // Distinguish bool from numeric so we don't accidentally turn true → 1.
                if CFGetTypeID(n) == CFBooleanGetTypeID() { try container.encode(n.boolValue) }
                else if CFNumberIsFloatType(n) { try container.encode(n.doubleValue) }
                else { try container.encode(n.int64Value) }
            case is NSNull: try container.encodeNil()
            default:
                throw EncodingError.invalidValue(obj, EncodingError.Context(
                    codingPath: encoder.codingPath,
                    debugDescription: "Unsupported nested JSON value"
                ))
            }
        }
    }
}
