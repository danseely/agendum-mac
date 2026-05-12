import Foundation
import AgendumGitHub

/// Maps GitHub GraphQL response payloads into `[IncomingTask]` per
/// `docs/syncer-spec.md` §3.E (authored-PR enrichment), §3.F (issue
/// enrichment), §3.G (review-PR enrichment). Faithful port of the
/// per-repo + per-review loops in `../agendum/src/agendum/syncer.py:153-323`.
///
/// All mapping is pure (no I/O). Fetching is handled by `RepoFetcher` /
/// `ReviewFetcher`; this layer turns canned response shapes into the
/// sparse `IncomingTask` dicts the diff layer consumes.
public enum ResponseMapping {

    // MARK: - Per-repo bundle → [IncomingTask]

    /// Maps one repo's `fetchRepoData` response into incoming tasks.
    /// Returns nil if the repo was archived or the response was empty —
    /// matches Python's "skip if archived/empty" behavior in `syncer.py:147-149`.
    public static func mapRepoData(
        _ data: GHRepoQueryData,
        repoFullName: String,
        ghUser: String
    ) -> [IncomingTask]? {
        guard let repo = data.repository else { return nil }
        if repo.isArchived == true { return nil }

        var result: [IncomingTask] = []
        let shortName = GitHubStatusDerivation.extractRepoShortName(repoFullName)
        let userLower = ghUser.lowercased()

        // Authored PRs (open) — syncer.py:153-200
        if let prs = repo.authoredPRs?.nodes {
            for pr in prs {
                guard pr.author?.login?.lowercased() == userLower else { continue }
                result.append(mapAuthoredPR(pr, repoFullName: repoFullName, shortName: shortName, ghUser: ghUser))
            }
        }

        // Merged PRs (bare) — syncer.py:202-214
        if let prs = repo.mergedPRs?.nodes {
            for pr in prs {
                guard pr.author?.login?.lowercased() == userLower else { continue }
                result.append(bareTerminalPR(pr, status: "merged", repoFullName: repoFullName, shortName: shortName))
            }
        }

        // Closed PRs (bare) — syncer.py:215-227
        if let prs = repo.closedPRs?.nodes {
            for pr in prs {
                guard pr.author?.login?.lowercased() == userLower else { continue }
                result.append(bareTerminalPR(pr, status: "closed", repoFullName: repoFullName, shortName: shortName))
            }
        }

        // Open issues assigned to user — syncer.py:229-246
        if let issues = repo.openIssues?.nodes {
            for issue in issues {
                result.append(mapOpenIssue(issue, repoFullName: repoFullName, shortName: shortName))
            }
        }

        // Closed issues (bare) — syncer.py:248-257
        if let issues = repo.closedIssues?.nodes {
            for issue in issues {
                result.append(bareTerminalIssue(issue, repoFullName: repoFullName, shortName: shortName))
            }
        }

        return result
    }

    // MARK: - Single review-PR detail → IncomingTask

    /// Maps one PR's `fetchReviewDetail` response into an `IncomingTask` with
    /// `source = "pr_review"`. Falls back to the search-result `prInfo` when
    /// the detail response is missing fields.
    /// Returns nil if the pull request payload was absent (Python `syncer.py:275-277`).
    public static func mapReviewPR(
        detail: GHReviewQueryData,
        prInfo: GHSearchItem,
        repoFullName: String,
        ghUser: String
    ) -> IncomingTask? {
        guard let pr = detail.repository?.pullRequest else { return nil }
        let userLower = ghUser.lowercased()

        let reviews = pr.reviews?.nodes ?? []
        let userReviews = reviews.filter { ($0.author?.login ?? "").lowercased() == userLower }
        let userHasReviewed = !userReviews.isEmpty

        var newCommitsSince = false
        var reRequestedAfterReview = false
        if userHasReviewed {
            let lastReviewTime = userReviews
                .compactMap(\.submittedAt)
                .max() ?? ""
            let lastCommitTime = pr.commits?.nodes.first?.commit?.committedDate ?? ""
            if !lastCommitTime.isEmpty && !lastReviewTime.isEmpty {
                newCommitsSince = lastCommitTime > lastReviewTime
            }

            for event in pr.timelineItems?.nodes ?? [] {
                let reviewerLogin = (event.requestedReviewer?.login ?? "").lowercased()
                guard reviewerLogin == userLower else { continue }
                let createdAt = event.createdAt ?? ""
                if !createdAt.isEmpty && createdAt > lastReviewTime {
                    reRequestedAfterReview = true
                    break
                }
            }
        }

        let status = GitHubStatusDerivation.deriveReviewPullRequestStatus(
            from: ReviewPullRequestStatusInput(
                userHasReviewed: userHasReviewed,
                newCommitsSinceReview: newCommitsSince,
                reRequestedAfterReview: reRequestedAfterReview
            )
        )

        let authorLogin = pr.author?.login ?? ""
        let authorDisplayFirst = GitHubStatusDerivation.parseAuthorFirstName(pr.author?.name)

        let title = pr.title ?? prInfo.title ?? ""
        let url = pr.url ?? prInfo.url ?? ""
        let number = pr.number != 0 ? pr.number : (prInfo.number ?? 0)

        var present: Set<IncomingTask.Field> = [
            .title, .source, .status, .ghURL, .ghNumber,
            .ghRepo, .project, .ghAuthor, .ghAuthorName, .tags
        ]
        if number == 0 { present.remove(.ghNumber) }

        return IncomingTask(
            title: title,
            source: "pr_review",
            status: status,
            ghURL: url,
            ghNumber: number == 0 ? nil : number,
            ghRepo: repoFullName,
            project: GitHubStatusDerivation.extractRepoShortName(repoFullName),
            ghAuthor: authorLogin.isEmpty ? nil : authorLogin,
            ghAuthorName: authorDisplayFirst ?? (authorLogin.isEmpty ? nil : authorLogin),
            tags: encodeTags(["review"]),
            presentFields: present
        )
    }

    // MARK: - Private — per-shape mappers

    private static func mapAuthoredPR(
        _ pr: GHRepoAuthoredPR,
        repoFullName: String,
        shortName: String,
        ghUser: String
    ) -> IncomingTask {
        let userLower = ghUser.lowercased()
        let reviews = pr.reviews?.nodes ?? []
        // Filter qualifying reviews — syncer.py:158-165. Python uses
        // `state not in (…)` which is permissive on null; mirror that here
        // by skipping the state check only when state is nil.
        let qualifyingReviews = reviews.filter { review in
            let authorMatches = (review.author?.login ?? "").lowercased() != userLower
            let hasSubmitted = (review.submittedAt ?? "").isEmpty == false
            let hasID = (review.id ?? "").isEmpty == false
            let stateOK: Bool
            if let state = review.state {
                stateOK = !["APPROVED", "CHANGES_REQUESTED", "PENDING"].contains(state)
            } else {
                stateOK = true // Permissive null — match Python.
            }
            return authorMatches && hasSubmitted && hasID && stateOK
        }

        let latestCommentReview = qualifyingReviews.max(by: { ($0.submittedAt ?? "") < ($1.submittedAt ?? "") })
        let latestCommitTime = pr.commits?.nodes.first?.commit?.committedDate

        // Build review-thread summaries for B2.
        let reviewThreads: [ReviewThreadSummary] = (pr.reviewThreads?.nodes ?? []).map { thread in
            let comments: [ReviewThreadCommentSummary] = (thread.comments?.nodes ?? []).map { c in
                ReviewThreadCommentSummary(
                    authorLogin: c.author?.login,
                    createdAt: c.createdAt,
                    pullRequestReviewID: c.pullRequestReview?.id
                )
            }
            return ReviewThreadSummary(isResolved: thread.isResolved ?? false, comments: comments)
        }

        let qualifyingReviewSummaries: [ReviewSummary] = qualifyingReviews.map { review in
            ReviewSummary(id: review.id, submittedAt: review.submittedAt)
        }

        let status = GitHubStatusDerivation.deriveAuthoredPullRequestStatus(
            from: AuthoredPullRequestStatusInput(
                isDraft: pr.isDraft ?? false,
                reviewDecision: pr.reviewDecision,
                state: pr.state,
                hasReviewRequests: (pr.reviewRequests?.totalCount ?? 0) > 0,
                latestCommitTime: latestCommitTime,
                latestCommentReviewID: latestCommentReview?.id,
                latestCommentReviewTime: latestCommentReview?.submittedAt,
                qualifyingReviews: qualifyingReviewSummaries,
                authorLogin: pr.author?.login,
                reviewThreads: reviewThreads
            )
        )

        let labels = (pr.labels?.nodes ?? []).map(\.name)
        let tagsJSON = labels.isEmpty ? nil : encodeTags(labels)

        return IncomingTask(
            title: pr.title,
            source: "pr_authored",
            status: status,
            ghURL: pr.url,
            ghNumber: pr.number,
            ghRepo: repoFullName,
            project: shortName,
            tags: tagsJSON,
            presentFields: [.title, .source, .status, .ghURL, .ghNumber, .ghRepo, .project, .tags]
        )
    }

    private static func bareTerminalPR(
        _ pr: GHTerminalPR,
        status: String,
        repoFullName: String,
        shortName: String
    ) -> IncomingTask {
        IncomingTask(
            title: "",
            source: "pr_authored",
            status: status,
            ghURL: pr.url,
            ghNumber: pr.number,
            ghRepo: repoFullName,
            project: shortName,
            presentFields: [.title, .source, .status, .ghURL, .ghNumber, .ghRepo, .project]
        )
    }

    private static func mapOpenIssue(
        _ issue: GHRepoIssue,
        repoFullName: String,
        shortName: String
    ) -> IncomingTask {
        // hasLinkedPR — syncer.py:230-234: any timeline node with subject.url OR source.url.
        let timeline = issue.timelineItems?.nodes ?? []
        let hasLinkedPR = timeline.contains { node in
            let subjectURL = node.subject?.url
            let sourceURL = node.source?.url
            return (subjectURL?.isEmpty == false) || (sourceURL?.isEmpty == false)
        }
        let status = GitHubStatusDerivation.deriveIssueStatus(
            state: issue.state,
            hasLinkedPullRequest: hasLinkedPR
        )
        let labels = (issue.labels?.nodes ?? []).map(\.name)
        let tagsJSON = labels.isEmpty ? nil : encodeTags(labels)

        return IncomingTask(
            title: issue.title,
            source: "issue",
            status: status,
            ghURL: issue.url,
            ghNumber: issue.number,
            ghRepo: repoFullName,
            project: shortName,
            tags: tagsJSON,
            presentFields: [.title, .source, .status, .ghURL, .ghNumber, .ghRepo, .project, .tags]
        )
    }

    private static func bareTerminalIssue(
        _ issue: GHTerminalIssue,
        repoFullName: String,
        shortName: String
    ) -> IncomingTask {
        IncomingTask(
            title: "",
            source: "issue",
            status: "closed",
            ghURL: issue.url,
            ghNumber: issue.number,
            ghRepo: repoFullName,
            project: shortName,
            presentFields: [.title, .source, .status, .ghURL, .ghNumber, .ghRepo, .project]
        )
    }

    // MARK: - Private — tag encoding

    /// JSON-encodes a tag list to match the format Python's `add_task` writes
    /// to the `tags` column. Used for both label arrays and the synthetic
    /// `["review"]` tag on pr_review rows.
    static func encodeTags(_ tags: [String]) -> String {
        // Use a stable shape: JSON array of strings, no spaces (matches what
        // `JSONSerialization.data(withJSONObject:)` emits). Python uses
        // `json.dumps(...)` which emits `["a", "b"]` with spaces; both decode
        // identically, so this is functionally equivalent.
        let data: Data
        do {
            data = try JSONSerialization.data(withJSONObject: tags)
        } catch {
            return "[]"
        }
        return String(data: data, encoding: .utf8) ?? "[]"
    }
}
