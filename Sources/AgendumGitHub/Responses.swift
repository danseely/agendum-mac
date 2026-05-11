import Foundation

// MARK: - GraphQL envelope

/// Top-level GraphQL response envelope. `data` may be `nil` on total failure;
/// `errors` may be non-`nil` even when `data` is present (partial success).
///
/// Note: generic parameter is `Payload` rather than `Data` to avoid shadowing
/// `Foundation.Data` inside the type.
public struct GHGraphQLResponse<Payload: Decodable & Sendable>: Decodable, Sendable {
    public let data: Payload?
    public let errors: [GHGraphQLError]?

    public init(data: Payload?, errors: [GHGraphQLError]?) {
        self.data = data
        self.errors = errors
    }
}

public struct GHGraphQLError: Decodable, Sendable, Equatable, CustomStringConvertible {
    public let message: String
    public let type: String?
    public let path: [GHGraphQLPathSegment]?

    public init(message: String, type: String? = nil, path: [GHGraphQLPathSegment]? = nil) {
        self.message = message
        self.type = type
        self.path = path
    }

    public var description: String {
        if let path, !path.isEmpty {
            return "\(message) (at \(path.map(\.description).joined(separator: ".")))"
        }
        return message
    }
}

/// Per the GraphQL spec, a `path` segment is either a field name (String) or
/// a list index (Int). Swift Codable can't natively decode either-or; we
/// model it as a small enum and decode by trying each form.
public enum GHGraphQLPathSegment: Decodable, Sendable, Equatable, CustomStringConvertible {
    case key(String)
    case index(Int)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let s = try? container.decode(String.self) {
            self = .key(s); return
        }
        if let i = try? container.decode(Int.self) {
            self = .index(i); return
        }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "GraphQL path segment must be String or Int")
    }

    public var description: String {
        switch self {
        case .key(let s): return s
        case .index(let i): return "[\(i)]"
        }
    }
}

// MARK: - REPO_QUERY response

public struct GHRepoQueryData: Decodable, Sendable {
    public let repository: GHRepoQueryRepository?
}

public struct GHRepoQueryRepository: Decodable, Sendable {
    public let isArchived: Bool?
    public let openIssues: GHNodes<GHRepoIssue>?
    public let closedIssues: GHNodes<GHTerminalIssue>?
    public let authoredPRs: GHNodes<GHRepoAuthoredPR>?
    public let mergedPRs: GHNodes<GHTerminalPR>?
    public let closedPRs: GHNodes<GHTerminalPR>?
}

/// Wraps GraphQL's `{ nodes: [T] }` collection shape.
///
/// GitHub sometimes returns `"nodes": null` on connection fields when there's
/// nothing to return (and also on partial-permission responses). Treat null
/// and missing as equivalent to an empty array so one stale repo doesn't take
/// out the whole sync.
public struct GHNodes<Node: Decodable & Sendable>: Decodable, Sendable {
    public let nodes: [Node]

    private enum CodingKeys: String, CodingKey { case nodes }

    public init(nodes: [Node]) { self.nodes = nodes }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // decodeIfPresent treats both missing key and explicit null as nil → []
        self.nodes = try container.decodeIfPresent([Node].self, forKey: .nodes) ?? []
    }
}

public struct GHRepoIssue: Decodable, Sendable {
    public let number: Int
    public let title: String
    public let url: String
    public let state: String
    public let createdAt: String?
    public let labels: GHNodes<GHLabel>?
    public let timelineItems: GHNodes<GHIssueTimelineNode>?
}

public struct GHTerminalIssue: Decodable, Sendable {
    public let number: Int
    public let url: String
    public let state: String
}

public struct GHTerminalPR: Decodable, Sendable {
    public let number: Int
    public let url: String
    public let state: String
    public let author: GHAuthor?
}

public struct GHRepoAuthoredPR: Decodable, Sendable {
    public let number: Int
    public let title: String
    public let url: String
    public let state: String
    public let isDraft: Bool?
    public let createdAt: String?
    public let headRefName: String?
    public let author: GHAuthor?
    public let reviewDecision: String?
    public let reviewRequests: GHReviewRequests?
    public let commits: GHCommits?
    public let reviews: GHNodes<GHReview>?
    public let reviewThreads: GHNodes<GHReviewThread>?
    public let labels: GHNodes<GHLabel>?
}

public struct GHAuthor: Decodable, Sendable {
    /// `null` for deleted users / bot accounts without a login.
    public let login: String?
    /// Only present on `... on User { name }` fragments; nil for bots and orgs.
    public let name: String?
}

public struct GHReviewRequests: Decodable, Sendable {
    public let totalCount: Int
}

public struct GHCommits: Decodable, Sendable {
    public let nodes: [GHCommitNode]

    private enum CodingKeys: String, CodingKey { case nodes }

    public init(nodes: [GHCommitNode]) { self.nodes = nodes }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.nodes = try container.decodeIfPresent([GHCommitNode].self, forKey: .nodes) ?? []
    }
}

public struct GHCommitNode: Decodable, Sendable {
    public let commit: GHCommit?
}

public struct GHCommit: Decodable, Sendable {
    public let committedDate: String?
}

public struct GHReview: Decodable, Sendable {
    public let id: String?
    public let state: String?
    public let submittedAt: String?
    public let author: GHAuthor?
}

public struct GHReviewThread: Decodable, Sendable {
    public let isResolved: Bool?
    public let isOutdated: Bool?
    public let comments: GHNodes<GHReviewComment>?
}

public struct GHReviewComment: Decodable, Sendable {
    public let createdAt: String?
    public let pullRequestReview: GHReviewID?
    public let author: GHAuthor?
}

public struct GHReviewID: Decodable, Sendable {
    public let id: String?
}

public struct GHLabel: Decodable, Sendable {
    public let name: String
}

/// Union of `ConnectedEvent { subject { ... on PullRequest { url } } }`
/// and `CrossReferencedEvent { source { ... on PullRequest { url } } }`.
/// Either or both fields may be present per the GraphQL inline fragments.
public struct GHIssueTimelineNode: Decodable, Sendable {
    public let subject: GHURLContainer?
    public let source: GHURLContainer?
}

public struct GHURLContainer: Decodable, Sendable {
    public let url: String?
}

// MARK: - REVIEW_QUERY response

public struct GHReviewQueryData: Decodable, Sendable {
    public let repository: GHReviewQueryRepository?
}

public struct GHReviewQueryRepository: Decodable, Sendable {
    public let pullRequest: GHReviewQueryPR?
}

public struct GHReviewQueryPR: Decodable, Sendable {
    public let number: Int
    public let title: String?
    public let url: String?
    public let state: String?
    public let createdAt: String?
    public let isDraft: Bool?
    public let headRefName: String?
    public let author: GHAuthor?
    public let commits: GHCommits?
    public let reviews: GHNodes<GHReviewQueryReview>?
    public let timelineItems: GHNodes<GHReviewRequestedEvent>?
}

public struct GHReviewQueryReview: Decodable, Sendable {
    public let author: GHAuthor?
    public let submittedAt: String?
    public let state: String?
}

public struct GHReviewRequestedEvent: Decodable, Sendable {
    public let createdAt: String?
    public let requestedReviewer: GHRequestedReviewer?
}

public struct GHRequestedReviewer: Decodable, Sendable {
    public let login: String?
}

// MARK: - REST responses

/// `GET /user` returns the authenticated user; we read only `.login`.
public struct GHUserResponse: Decodable, Sendable {
    public let login: String
}

/// `gh search prs/issues ... --json repository,...` returns a list of these.
/// We model the minimum used by `discover_repos` / `discover_review_prs`.
public struct GHSearchItem: Decodable, Sendable {
    public let number: Int?
    public let title: String?
    public let url: String?
    public let repository: GHSearchRepository?
    public let author: GHAuthor?
}

public struct GHSearchRepository: Decodable, Sendable {
    public let nameWithOwner: String?
    public let name: String?
}
