import Foundation
import AgendumGitHub

/// Narrow seam over `GitHubClient` covering exactly the calls
/// `ReviewFetcher` needs. Tests substitute a fake without touching transport.
public protocol ReviewFetchClient: Sendable {
    func discoverReviewPRs(orgs: [String], user: String) async throws -> (prs: [GHSearchItem], ok: Bool)
    func fetchReviewDetail(owner: String, name: String, number: Int) async throws
        -> (data: GHReviewQueryData, partialErrors: [GHGraphQLError])
}

extension GitHubClient: ReviewFetchClient {}

/// Review-requested PR fetch path — port of `syncer.py:261-323`.
///
/// Review discovery is org-scoped in the original CLI. Repo-only workspaces
/// therefore cannot prove completeness, so they return `reviewFetchOK = false`
/// to keep `diffTasks` from closing existing `pr_review` rows.
public func fetchReviewTasks(
    config: WorkspaceRepoConfig,
    user: String,
    client: any ReviewFetchClient
) async -> (incoming: [IncomingTask], reviewFetchOK: Bool) {
    var reviewFetchOK = true
    let reviewPRs: [GHSearchItem]

    if config.orgs.isEmpty {
        reviewPRs = []
    } else {
        do {
            let result = try await client.discoverReviewPRs(orgs: config.orgs, user: user)
            reviewPRs = result.prs
            reviewFetchOK = result.ok
        } catch {
            logger.error("ReviewFetcher: discovery failed: \(error.localizedDescription, privacy: .public)")
            reviewPRs = []
            reviewFetchOK = false
        }
    }

    if !config.repos.isEmpty && config.orgs.isEmpty {
        reviewFetchOK = false
    }

    let allowList = Set(config.repos)
    var incoming: [IncomingTask] = []
    incoming.reserveCapacity(reviewPRs.count)

    for prInfo in reviewPRs {
        guard let repoFullName = repoFullName(from: prInfo) else {
            logger.warning("ReviewFetcher: skipping PR without owner/name repository")
            continue
        }
        guard !config.excludeRepos.contains(repoFullName) else { continue }
        guard allowList.isEmpty || allowList.contains(repoFullName) else { continue }
        guard let (owner, name) = splitRepoFullName(repoFullName) else {
            logger.warning("ReviewFetcher: malformed repo entry \(repoFullName, privacy: .public)")
            continue
        }
        guard let number = prInfo.number, number > 0 else {
            logger.warning("ReviewFetcher: skipping review PR in \(repoFullName, privacy: .public) without a number")
            continue
        }

        do {
            let (detail, _) = try await client.fetchReviewDetail(owner: owner, name: name, number: number)
            if let task = ResponseMapping.mapReviewPR(
                detail: detail,
                prInfo: prInfo,
                repoFullName: repoFullName,
                ghUser: user
            ) {
                incoming.append(task)
            }
        } catch {
            logger.error(
                "ReviewFetcher: \(repoFullName)#\(number, privacy: .public) failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    return (incoming, reviewFetchOK)
}

private func repoFullName(from item: GHSearchItem) -> String? {
    if let nameWithOwner = item.repository?.nameWithOwner, isFullRepoName(nameWithOwner) {
        return nameWithOwner
    }
    if let name = item.repository?.name, isFullRepoName(name) {
        return name
    }
    return repoFullName(fromURL: item.url)
}

private func repoFullName(fromURL rawURL: String?) -> String? {
    guard let rawURL, let url = URL(string: rawURL) else { return nil }
    let parts = url.pathComponents.filter { $0 != "/" }
    guard parts.count >= 2 else { return nil }
    let owner = parts[0]
    let name = parts[1]
    guard !owner.isEmpty, !name.isEmpty else { return nil }
    return "\(owner)/\(name)"
}

private func splitRepoFullName(_ repoFullName: String) -> (owner: String, name: String)? {
    let parts = repoFullName.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
    guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
    return (String(parts[0]), String(parts[1]))
}

private func isFullRepoName(_ value: String) -> Bool {
    splitRepoFullName(value) != nil
}
