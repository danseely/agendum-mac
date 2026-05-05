@testable import AgendumMacCore
import Foundation
import Testing

struct GitHubStatusDerivationTests {
    @Test
    func authoredPullRequestStatusesMatchFixture() throws {
        let fixture = try loadFixture()

        for testCase in fixture.authoredPullRequests {
            let actual = GitHubStatusDerivation.deriveAuthoredPullRequestStatus(from: testCase.input)
            #expect(actual == testCase.expected, "\(testCase.name)")
        }
    }

    @Test
    func reviewPullRequestStatusesMatchFixture() throws {
        let fixture = try loadFixture()

        for testCase in fixture.reviewPullRequests {
            let actual = GitHubStatusDerivation.deriveReviewPullRequestStatus(from: testCase.input)
            #expect(actual == testCase.expected, "\(testCase.name)")
        }
    }

    @Test
    func issueStatusesMatchFixture() throws {
        let fixture = try loadFixture()

        for testCase in fixture.issues {
            let actual = GitHubStatusDerivation.deriveIssueStatus(
                state: testCase.input.state,
                hasLinkedPullRequest: testCase.input.hasLinkedPullRequest
            )
            #expect(actual == testCase.expected, "\(testCase.name)")
        }
    }

    @Test
    func reviewFeedbackFlagsMatchFixture() throws {
        let fixture = try loadFixture()

        for testCase in fixture.reviewFeedback {
            let actual = GitHubStatusDerivation.hasUnacknowledgedReviewFeedback(testCase.input)
            #expect(actual == testCase.expected, "\(testCase.name)")
        }
    }

    @Test
    func authorFirstNamesMatchFixture() throws {
        let fixture = try loadFixture()

        for testCase in fixture.authorFirstNames {
            let actual = GitHubStatusDerivation.parseAuthorFirstName(testCase.displayName)
            #expect(actual == testCase.expected, "\(testCase.name)")
        }
    }

    @Test
    func repoShortNamesMatchFixture() throws {
        let fixture = try loadFixture()

        for testCase in fixture.repoShortNames {
            let actual = GitHubStatusDerivation.extractRepoShortName(testCase.fullRepo)
            #expect(actual == testCase.expected, "\(testCase.name)")
        }
    }
}

private func loadFixture() throws -> StatusDerivationFixture {
    let url = try #require(
        Bundle.module.url(
            forResource: "GitHubStatusDerivationCases",
            withExtension: "json"
        )
    )
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(StatusDerivationFixture.self, from: data)
}

private struct StatusDerivationFixture: Decodable {
    let authoredPullRequests: [AuthoredPullRequestCase]
    let reviewPullRequests: [ReviewPullRequestCase]
    let issues: [IssueCase]
    let reviewFeedback: [ReviewFeedbackCase]
    let authorFirstNames: [AuthorFirstNameCase]
    let repoShortNames: [RepoShortNameCase]
}

private struct AuthoredPullRequestCase: Decodable {
    let name: String
    let input: AuthoredPullRequestStatusInput
    let expected: String
}

private struct ReviewPullRequestCase: Decodable {
    let name: String
    let input: ReviewPullRequestStatusInput
    let expected: String
}

private struct IssueCase: Decodable {
    let name: String
    let input: IssueInput
    let expected: String
}

private struct IssueInput: Decodable {
    let state: String
    let hasLinkedPullRequest: Bool
}

private struct ReviewFeedbackCase: Decodable {
    let name: String
    let input: ReviewFeedbackInput
    let expected: Bool
}

private struct AuthorFirstNameCase: Decodable {
    let name: String
    let displayName: String?
    let expected: String?
}

private struct RepoShortNameCase: Decodable {
    let name: String
    let fullRepo: String
    let expected: String
}
