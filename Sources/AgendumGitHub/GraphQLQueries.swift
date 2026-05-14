/// GraphQL query strings sent to `https://api.github.com/graphql`.
///
/// Faithful to `../agendum/src/agendum/gh.py` `REPO_QUERY` and `REVIEW_QUERY`
/// — preserved so a future post-MVP slice can add fields or migrate to typed
/// codegen without re-deriving the contract from Python.
enum GraphQLQueries {
    /// Per-repo authored PRs + assigned issues + recent merged/closed batches.
    /// Variables: `owner: String!`, `name: String!`, `user: String!`.
    static let repo = """
    query($owner: String!, $name: String!, $user: String!) {
      repository(owner: $owner, name: $name) {
        isArchived
        openIssues: issues(
          first: 50, states: OPEN,
          filterBy: {assignee: $user}
        ) {
          nodes {
            number title url state createdAt
            labels(first: 10) { nodes { name } }
            timelineItems(last: 20, itemTypes: [CONNECTED_EVENT, CROSS_REFERENCED_EVENT]) {
              nodes {
                ... on ConnectedEvent { subject { ... on PullRequest { url } } }
                ... on CrossReferencedEvent { source { ... on PullRequest { url } } }
              }
            }
          }
        }
        closedIssues: issues(
          first: 20, states: CLOSED,
          filterBy: {assignee: $user}
          orderBy: {field: UPDATED_AT, direction: DESC}
        ) {
          nodes { number url state }
        }
        authoredPRs: pullRequests(
          first: 50, states: OPEN,
          orderBy: {field: UPDATED_AT, direction: DESC}
        ) {
          nodes {
            number title url state isDraft createdAt
            headRefName
            author { login }
            reviewDecision
            reviewRequests(first: 10) { totalCount }
            commits(last: 1) {
              nodes {
                commit {
                  committedDate
                }
              }
            }
            reviews(last: 20) {
              nodes {
                id
                state
                submittedAt
                author { login }
              }
            }
            reviewThreads(last: 50) {
              nodes {
                isResolved
                isOutdated
                comments(last: 20) {
                  nodes {
                    createdAt
                    pullRequestReview { id }
                    author { login }
                  }
                }
              }
            }
            labels(first: 10) { nodes { name } }
          }
        }
        mergedPRs: pullRequests(
          first: 20, states: MERGED,
          orderBy: {field: UPDATED_AT, direction: DESC}
        ) {
          nodes { number url state author { login } }
        }
        closedPRs: pullRequests(
          first: 20, states: CLOSED,
          orderBy: {field: UPDATED_AT, direction: DESC}
        ) {
          nodes { number url state author { login } }
        }
      }
    }
    """

    /// Per-PR review detail used to decide review-task status
    /// (re-request-after-review / new-commits-since-review).
    /// Variables: `owner: String!`, `name: String!`, `number: Int!`.
    static let review = """
    query($owner: String!, $name: String!, $number: Int!) {
      repository(owner: $owner, name: $name) {
        pullRequest(number: $number) {
          number title url state createdAt isDraft
          headRefName
          author {
            login
            ... on User {
              name
            }
          }
          commits(last: 1) { nodes { commit { committedDate } } }
          reviews(first: 50) {
            nodes { author { login } submittedAt state }
          }
          timelineItems(last: 50, itemTypes: [REVIEW_REQUESTED_EVENT]) {
            nodes {
              ... on ReviewRequestedEvent {
                createdAt
                requestedReviewer {
                  ... on User { login }
                }
              }
            }
          }
        }
      }
    }
    """
}
