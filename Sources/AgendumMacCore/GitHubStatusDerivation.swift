import Foundation

public enum GitHubStatusDerivation {
    public static func deriveAuthoredPullRequestStatus(from input: AuthoredPullRequestStatusInput) -> String {
        if input.state == "MERGED" {
            return "merged"
        }
        if input.state == "CLOSED" {
            return "closed"
        }
        if input.isDraft {
            return "draft"
        }
        if input.reviewDecision == "APPROVED" {
            return "approved"
        }
        if input.reviewDecision == "CHANGES_REQUESTED" {
            return "changes requested"
        }
        if hasUnacknowledgedReviewFeedback(
            ReviewFeedbackInput(
                latestCommentReviewID: input.latestCommentReviewID,
                latestCommentReviewTime: input.latestCommentReviewTime,
                latestCommitTime: input.latestCommitTime,
                authorLogin: input.authorLogin,
                qualifyingReviews: input.qualifyingReviews,
                reviewThreads: input.reviewThreads
            )
        ) {
            return "review received"
        }
        if input.hasReviewRequests {
            return "awaiting review"
        }
        return "open"
    }

    public static func deriveReviewPullRequestStatus(from input: ReviewPullRequestStatusInput) -> String {
        if !input.userHasReviewed {
            return "review requested"
        }
        if input.reRequestedAfterReview || input.newCommitsSinceReview {
            return "re-review requested"
        }
        return "reviewed"
    }

    public static func deriveIssueStatus(state: String, hasLinkedPullRequest: Bool) -> String {
        if state == "CLOSED" {
            return "closed"
        }
        if hasLinkedPullRequest {
            return "in progress"
        }
        return "open"
    }

    public static func parseAuthorFirstName(_ displayName: String?) -> String? {
        guard let displayName, !displayName.isEmpty else {
            return nil
        }
        return displayName.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ").first.map(String.init)
    }

    public static func extractRepoShortName(_ fullRepo: String) -> String {
        guard let slash = fullRepo.firstIndex(of: "/") else {
            return fullRepo
        }
        return String(fullRepo[fullRepo.index(after: slash)...])
    }

    public static func hasUnacknowledgedReviewFeedback(_ input: ReviewFeedbackInput) -> Bool {
        var reviews = input.qualifyingReviews
        if reviews.isEmpty, let latestID = input.latestCommentReviewID, let latestTime = input.latestCommentReviewTime {
            reviews = [
                ReviewSummary(id: latestID, submittedAt: latestTime)
            ]
        }
        if reviews.isEmpty {
            return false
        }

        let commitDate = parseGitHubDate(input.latestCommitTime)

        for review in reviews {
            guard let reviewID = review.id, let reviewTime = review.submittedAt else {
                continue
            }

            let relevantThreads = relevantReviewThreads(input.reviewThreads, reviewID: reviewID)
            if !relevantThreads.isEmpty {
                for thread in relevantThreads {
                    if thread.isResolved {
                        continue
                    }
                    if let authorLogin = input.authorLogin,
                       threadHasAuthorReplyAfter(thread, authorLogin: authorLogin, reviewTime: reviewTime) {
                        continue
                    }
                    return true
                }
                continue
            }

            let reviewDate = parseGitHubDate(reviewTime)
            if reviewDate == nil || commitDate == nil || commitDate! <= reviewDate! {
                return true
            }
        }

        return false
    }

    private static func parseGitHubDate(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else {
            return nil
        }

        let normalized = value.replacingOccurrences(of: "Z", with: "+00:00")
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime]
        let fractionalDateFormatter = ISO8601DateFormatter()
        fractionalDateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return dateFormatter.date(from: normalized) ?? fractionalDateFormatter.date(from: normalized)
    }

    private static func threadHasAuthorReplyAfter(
        _ thread: ReviewThreadSummary,
        authorLogin: String,
        reviewTime: String
    ) -> Bool {
        for comment in thread.comments {
            let commentAuthor = comment.authorLogin ?? ""
            if commentAuthor.lowercased() == authorLogin.lowercased(),
               let createdAt = comment.createdAt,
               createdAt > reviewTime {
                return true
            }
        }
        return false
    }

    private static func relevantReviewThreads(
        _ reviewThreads: [ReviewThreadSummary],
        reviewID: String
    ) -> [ReviewThreadSummary] {
        reviewThreads.filter { thread in
            thread.comments.contains { comment in
                comment.pullRequestReviewID == reviewID
            }
        }
    }
}

public struct AuthoredPullRequestStatusInput: Codable, Equatable, Sendable {
    public let isDraft: Bool
    public let reviewDecision: String?
    public let state: String
    public let hasReviewRequests: Bool
    public let latestCommitTime: String?
    public let latestCommentReviewID: String?
    public let latestCommentReviewTime: String?
    public let qualifyingReviews: [ReviewSummary]
    public let authorLogin: String?
    public let reviewThreads: [ReviewThreadSummary]

    public init(
        isDraft: Bool,
        reviewDecision: String?,
        state: String,
        hasReviewRequests: Bool = false,
        latestCommitTime: String? = nil,
        latestCommentReviewID: String? = nil,
        latestCommentReviewTime: String? = nil,
        qualifyingReviews: [ReviewSummary] = [],
        authorLogin: String? = nil,
        reviewThreads: [ReviewThreadSummary] = []
    ) {
        self.isDraft = isDraft
        self.reviewDecision = reviewDecision
        self.state = state
        self.hasReviewRequests = hasReviewRequests
        self.latestCommitTime = latestCommitTime
        self.latestCommentReviewID = latestCommentReviewID
        self.latestCommentReviewTime = latestCommentReviewTime
        self.qualifyingReviews = qualifyingReviews
        self.authorLogin = authorLogin
        self.reviewThreads = reviewThreads
    }
}

public struct ReviewPullRequestStatusInput: Codable, Equatable, Sendable {
    public let userHasReviewed: Bool
    public let newCommitsSinceReview: Bool
    public let reRequestedAfterReview: Bool

    public init(
        userHasReviewed: Bool,
        newCommitsSinceReview: Bool,
        reRequestedAfterReview: Bool = false
    ) {
        self.userHasReviewed = userHasReviewed
        self.newCommitsSinceReview = newCommitsSinceReview
        self.reRequestedAfterReview = reRequestedAfterReview
    }
}

public struct ReviewFeedbackInput: Codable, Equatable, Sendable {
    public let latestCommentReviewID: String?
    public let latestCommentReviewTime: String?
    public let latestCommitTime: String?
    public let authorLogin: String?
    public let qualifyingReviews: [ReviewSummary]
    public let reviewThreads: [ReviewThreadSummary]

    public init(
        latestCommentReviewID: String? = nil,
        latestCommentReviewTime: String? = nil,
        latestCommitTime: String? = nil,
        authorLogin: String? = nil,
        qualifyingReviews: [ReviewSummary] = [],
        reviewThreads: [ReviewThreadSummary] = []
    ) {
        self.latestCommentReviewID = latestCommentReviewID
        self.latestCommentReviewTime = latestCommentReviewTime
        self.latestCommitTime = latestCommitTime
        self.authorLogin = authorLogin
        self.qualifyingReviews = qualifyingReviews
        self.reviewThreads = reviewThreads
    }
}

public struct ReviewSummary: Codable, Equatable, Sendable {
    public let id: String?
    public let submittedAt: String?

    public init(id: String?, submittedAt: String?) {
        self.id = id
        self.submittedAt = submittedAt
    }
}

public struct ReviewThreadSummary: Codable, Equatable, Sendable {
    public let isResolved: Bool
    public let comments: [ReviewThreadCommentSummary]

    public init(isResolved: Bool = false, comments: [ReviewThreadCommentSummary] = []) {
        self.isResolved = isResolved
        self.comments = comments
    }
}

public struct ReviewThreadCommentSummary: Codable, Equatable, Sendable {
    public let authorLogin: String?
    public let createdAt: String?
    public let pullRequestReviewID: String?

    public init(authorLogin: String?, createdAt: String?, pullRequestReviewID: String?) {
        self.authorLogin = authorLogin
        self.createdAt = createdAt
        self.pullRequestReviewID = pullRequestReviewID
    }
}
