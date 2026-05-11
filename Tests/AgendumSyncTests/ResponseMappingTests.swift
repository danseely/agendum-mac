@testable import AgendumSync
import AgendumGitHub
import Foundation
import Testing

@Suite("ResponseMapping")
struct ResponseMappingTests {

    // MARK: - REPO_QUERY happy path

    @Test
    func happyPathRepoYieldsAllFiveBuckets() throws {
        let data = try decodeRepo("repoQueryHappyPath_acme_widget")
        let tasks = try #require(ResponseMapping.mapRepoData(data, repoFullName: "acme/widget", ghUser: "danseely"))

        // 1 open issue + 1 closed issue + 1 authored PR + 1 merged PR + 1 closed PR = 5 rows.
        #expect(tasks.count == 5)

        // The open issue: linked PR present → status "in progress".
        let openIssue = try #require(tasks.first(where: { $0.source == "issue" && $0.status == "in progress" }))
        #expect(openIssue.title == "Bug: nav drawer flickers")
        #expect(openIssue.ghURL == "https://github.com/acme/widget/issues/42")
        #expect(openIssue.ghNumber == 42)
        #expect(openIssue.ghRepo == "acme/widget")
        #expect(openIssue.project == "widget")
        #expect(openIssue.tags == #"["bug","ui"]"#)
        #expect(openIssue.presentFields.contains(.tags))

        // The closed issue: bare payload.
        let closedIssue = try #require(tasks.first(where: { $0.source == "issue" && $0.status == "closed" }))
        #expect(closedIssue.title == "")
        #expect(closedIssue.ghNumber == 30)
        #expect(!closedIssue.presentFields.contains(.tags))
        #expect(!closedIssue.presentFields.contains(.ghAuthor))

        // The authored PR (open).
        let authoredPR = try #require(tasks.first(where: { $0.source == "pr_authored" && $0.status != "merged" && $0.status != "closed" }))
        #expect(authoredPR.title == "Fix nav drawer flicker")
        #expect(authoredPR.ghNumber == 99)
        #expect(authoredPR.tags == #"["frontend"]"#)
        // Status derivation: not draft, no reviewDecision, hasReviewRequests=2,
        // qualifying COMMENTED review with unresolved thread → "review received".
        #expect(authoredPR.status == "review received")

        // The merged PR (bare).
        let mergedPR = try #require(tasks.first(where: { $0.source == "pr_authored" && $0.status == "merged" }))
        #expect(mergedPR.title == "")
        #expect(mergedPR.ghNumber == 88)

        // The closed PR (bare).
        let closedPR = try #require(tasks.first(where: { $0.source == "pr_authored" && $0.status == "closed" }))
        #expect(closedPR.title == "")
        #expect(closedPR.ghNumber == 77)
    }

    // MARK: - Authored-PR author filter

    @Test
    func authoredPRsFromOtherAuthorsAreFiltered() throws {
        let json = #"""
        {
          "data": {
            "repository": {
              "isArchived": false,
              "openIssues": {"nodes": []},
              "closedIssues": {"nodes": []},
              "authoredPRs": {
                "nodes": [
                  {
                    "number": 1, "title": "Mine", "url": "https://example/1",
                    "state": "OPEN", "isDraft": false, "createdAt": "2026-05-01T00:00:00Z",
                    "headRefName": "x", "author": {"login": "danseely"},
                    "reviewDecision": null,
                    "reviewRequests": {"totalCount": 0},
                    "commits": {"nodes": []},
                    "reviews": {"nodes": []},
                    "reviewThreads": {"nodes": []},
                    "labels": {"nodes": []}
                  },
                  {
                    "number": 2, "title": "Theirs", "url": "https://example/2",
                    "state": "OPEN", "isDraft": false, "createdAt": "2026-05-01T00:00:00Z",
                    "headRefName": "y", "author": {"login": "someone-else"},
                    "reviewDecision": null,
                    "reviewRequests": {"totalCount": 0},
                    "commits": {"nodes": []},
                    "reviews": {"nodes": []},
                    "reviewThreads": {"nodes": []},
                    "labels": {"nodes": []}
                  }
                ]
              },
              "mergedPRs": {"nodes": []},
              "closedPRs": {"nodes": []}
            }
          }
        }
        """#
        let data = try decode(GHRepoQueryData.self, json: json)
        let tasks = try #require(ResponseMapping.mapRepoData(data, repoFullName: "acme/widget", ghUser: "danseely"))
        #expect(tasks.map(\.title) == ["Mine"])
    }

    @Test
    func authoredFilterIsCaseInsensitive() throws {
        // `danseely` request matches author `DanSeely` (mixed case).
        let json = #"""
        {
          "data": {
            "repository": {
              "isArchived": false,
              "openIssues": {"nodes": []},
              "closedIssues": {"nodes": []},
              "authoredPRs": {
                "nodes": [
                  {
                    "number": 1, "title": "Mine", "url": "https://example/1",
                    "state": "OPEN", "isDraft": false, "createdAt": "2026-05-01T00:00:00Z",
                    "headRefName": "x", "author": {"login": "DanSeely"},
                    "reviewDecision": null,
                    "reviewRequests": {"totalCount": 0},
                    "commits": {"nodes": []},
                    "reviews": {"nodes": []},
                    "reviewThreads": {"nodes": []},
                    "labels": {"nodes": []}
                  }
                ]
              },
              "mergedPRs": {"nodes": []},
              "closedPRs": {"nodes": []}
            }
          }
        }
        """#
        let data = try decode(GHRepoQueryData.self, json: json)
        let tasks = try #require(ResponseMapping.mapRepoData(data, repoFullName: "acme/widget", ghUser: "danseely"))
        #expect(tasks.count == 1)
    }

    // MARK: - Archived repo / null repository

    @Test
    func archivedRepoMapsToNil() throws {
        let json = #"{"data": {"repository": {"isArchived": true, "openIssues": {"nodes": []}, "closedIssues": {"nodes": []}, "authoredPRs": {"nodes": []}, "mergedPRs": {"nodes": []}, "closedPRs": {"nodes": []}}}}"#
        let data = try decode(GHRepoQueryData.self, json: json)
        #expect(ResponseMapping.mapRepoData(data, repoFullName: "acme/widget", ghUser: "danseely") == nil)
    }

    @Test
    func nullRepositoryMapsToNil() throws {
        let json = #"{"data": {"repository": null}}"#
        let data = try decode(GHRepoQueryData.self, json: json)
        #expect(ResponseMapping.mapRepoData(data, repoFullName: "acme/widget", ghUser: "danseely") == nil)
    }

    // MARK: - REVIEW_QUERY happy path

    @Test
    func reviewDetailHappyPathProducesReviewedReRequestedTask() throws {
        // Fixture: user reviewed at 2026-05-08T17:00:00Z; commit at 2026-05-09T07:00:00Z;
        // review-requested event at 2026-05-09T06:00:00Z (BEFORE last commit).
        // → newCommitsSinceReview = true → status "re-review requested".
        let data = try decodeReview("reviewQueryHappyPath_acme_widget_1234")
        let prInfo = GHSearchItem(
            number: 1234, title: "Improve search",
            url: "https://github.com/acme/widget/pull/1234",
            repository: GHSearchRepository(nameWithOwner: "acme/widget", name: "widget"),
            author: GHAuthor(login: "octocat", name: nil)
        )
        let task = try #require(ResponseMapping.mapReviewPR(
            detail: data, prInfo: prInfo, repoFullName: "acme/widget", ghUser: "danseely"
        ))

        #expect(task.source == "pr_review")
        #expect(task.status == "re-review requested")
        #expect(task.title == "Improve search")
        #expect(task.ghURL == "https://github.com/acme/widget/pull/1234")
        #expect(task.ghNumber == 1234)
        #expect(task.ghRepo == "acme/widget")
        #expect(task.project == "widget")
        #expect(task.ghAuthor == "octocat")
        #expect(task.ghAuthorName == "Octo") // parseAuthorFirstName("Octo Cat") → "Octo"
        #expect(task.tags == #"["review"]"#)
    }

    @Test
    func reviewDetailWithNoUserReviewProducesReviewRequested() throws {
        // User has not reviewed → status "review requested".
        let json = #"""
        {
          "data": {
            "repository": {
              "pullRequest": {
                "number": 5, "title": "T", "url": "https://example/5", "state": "OPEN",
                "createdAt": "2026-05-01T00:00:00Z", "isDraft": false, "headRefName": "x",
                "author": {"login": "octocat", "name": "Octo Cat"},
                "commits": {"nodes": [{"commit": {"committedDate": "2026-05-09T07:00:00Z"}}]},
                "reviews": {"nodes": []},
                "timelineItems": {"nodes": []}
              }
            }
          }
        }
        """#
        let data = try decode(GHReviewQueryData.self, json: json)
        let prInfo = GHSearchItem(number: 5, title: "T", url: "https://example/5", repository: nil, author: nil)
        let task = try #require(ResponseMapping.mapReviewPR(
            detail: data, prInfo: prInfo, repoFullName: "acme/widget", ghUser: "danseely"
        ))
        #expect(task.status == "review requested")
        #expect(task.ghAuthorName == "Octo")
    }

    @Test
    func reviewDetailFallsBackToLoginWhenNoDisplayName() throws {
        let json = #"""
        {
          "data": {
            "repository": {
              "pullRequest": {
                "number": 5, "title": "T", "url": "https://example/5", "state": "OPEN",
                "createdAt": "2026-05-01T00:00:00Z", "isDraft": false, "headRefName": "x",
                "author": {"login": "botaccount"},
                "commits": {"nodes": []},
                "reviews": {"nodes": []},
                "timelineItems": {"nodes": []}
              }
            }
          }
        }
        """#
        let data = try decode(GHReviewQueryData.self, json: json)
        let prInfo = GHSearchItem(number: 5, title: "T", url: "https://example/5", repository: nil, author: nil)
        let task = try #require(ResponseMapping.mapReviewPR(
            detail: data, prInfo: prInfo, repoFullName: "acme/widget", ghUser: "danseely"
        ))
        #expect(task.ghAuthor == "botaccount")
        #expect(task.ghAuthorName == "botaccount") // no display name → login
    }

    @Test
    func reviewDetailWithNoPullRequestMapsToNil() throws {
        let json = #"{"data": {"repository": {"pullRequest": null}}}"#
        let data = try decode(GHReviewQueryData.self, json: json)
        let prInfo = GHSearchItem(number: 1, title: nil, url: nil, repository: nil, author: nil)
        #expect(ResponseMapping.mapReviewPR(
            detail: data, prInfo: prInfo, repoFullName: "acme/widget", ghUser: "danseely"
        ) == nil)
    }

    // MARK: - Authored-PR qualifying-reviews filter (per syncer-spec §3.E.2)

    @Test
    func qualifyingReviewsFilterExcludesByStateAuthorAndMissingFields() throws {
        // Build a PR with five reviews — only one should qualify:
        //   - APPROVED by stranger → excluded (state)
        //   - COMMENTED by user → excluded (own author)
        //   - COMMENTED by stranger, no submittedAt → excluded (missing field)
        //   - COMMENTED by stranger, no id → excluded (missing field)
        //   - COMMENTED by stranger, fully populated → qualifies
        let json = #"""
        {
          "data": {
            "repository": {
              "isArchived": false,
              "openIssues": {"nodes": []},
              "closedIssues": {"nodes": []},
              "authoredPRs": {
                "nodes": [{
                  "number": 1, "title": "PR", "url": "https://example/pr/1",
                  "state": "OPEN", "isDraft": false, "createdAt": "2026-05-01T00:00:00Z",
                  "headRefName": "x", "author": {"login": "danseely"},
                  "reviewDecision": null,
                  "reviewRequests": {"totalCount": 0},
                  "commits": {"nodes": [{"commit": {"committedDate": "2026-05-01T00:00:00Z"}}]},
                  "reviews": {
                    "nodes": [
                      {"id": "r1", "state": "APPROVED", "submittedAt": "2026-05-02T10:00:00Z", "author": {"login": "alice"}},
                      {"id": "r2", "state": "COMMENTED", "submittedAt": "2026-05-02T11:00:00Z", "author": {"login": "danseely"}},
                      {"id": "r3", "state": "COMMENTED", "submittedAt": null, "author": {"login": "bob"}},
                      {"id": null, "state": "COMMENTED", "submittedAt": "2026-05-02T12:00:00Z", "author": {"login": "carol"}},
                      {"id": "r5", "state": "COMMENTED", "submittedAt": "2026-05-02T13:00:00Z", "author": {"login": "dave"}}
                    ]
                  },
                  "reviewThreads": {"nodes": []},
                  "labels": {"nodes": []}
                }]
              },
              "mergedPRs": {"nodes": []},
              "closedPRs": {"nodes": []}
            }
          }
        }
        """#
        let data = try decode(GHRepoQueryData.self, json: json)
        let tasks = try #require(ResponseMapping.mapRepoData(data, repoFullName: "acme/widget", ghUser: "danseely"))
        #expect(tasks.count == 1)
        // Only the qualifying r5 review survives the filter; commit at 2026-05-01 ≤ review at
        // 2026-05-02 → hasUnacknowledged returns true → status "review received".
        #expect(tasks[0].status == "review received")
    }

    @Test
    func qualifyingReviewsFilterIsPermissiveOnNullState() throws {
        // Per syncer-spec §3.E.2 + Python parity: state=null does NOT exclude.
        let json = #"""
        {
          "data": {
            "repository": {
              "isArchived": false,
              "openIssues": {"nodes": []},
              "closedIssues": {"nodes": []},
              "authoredPRs": {
                "nodes": [{
                  "number": 1, "title": "PR", "url": "https://example/pr/1",
                  "state": "OPEN", "isDraft": false, "createdAt": "2026-05-01T00:00:00Z",
                  "headRefName": "x", "author": {"login": "danseely"},
                  "reviewDecision": null,
                  "reviewRequests": {"totalCount": 0},
                  "commits": {"nodes": [{"commit": {"committedDate": "2026-05-01T00:00:00Z"}}]},
                  "reviews": {
                    "nodes": [
                      {"id": "r1", "state": null, "submittedAt": "2026-05-02T10:00:00Z", "author": {"login": "alice"}}
                    ]
                  },
                  "reviewThreads": {"nodes": []},
                  "labels": {"nodes": []}
                }]
              },
              "mergedPRs": {"nodes": []},
              "closedPRs": {"nodes": []}
            }
          }
        }
        """#
        let data = try decode(GHRepoQueryData.self, json: json)
        let tasks = try #require(ResponseMapping.mapRepoData(data, repoFullName: "acme/widget", ghUser: "danseely"))
        // Null-state review qualifies (permissive); commit ≤ review → "review received".
        #expect(tasks[0].status == "review received")
    }

    // MARK: - Issue linked-PR detection (per syncer-spec §3.F)

    @Test
    func issueWithLinkedPRViaConnectedEventGetsInProgressStatus() throws {
        let json = #"""
        {
          "data": {
            "repository": {
              "isArchived": false,
              "openIssues": {
                "nodes": [{
                  "number": 1, "title": "T", "url": "https://example/issues/1",
                  "state": "OPEN", "createdAt": "2026-05-01T00:00:00Z",
                  "labels": {"nodes": []},
                  "timelineItems": {
                    "nodes": [{"subject": {"url": "https://example/pr/9"}}]
                  }
                }]
              },
              "closedIssues": {"nodes": []},
              "authoredPRs": {"nodes": []},
              "mergedPRs": {"nodes": []},
              "closedPRs": {"nodes": []}
            }
          }
        }
        """#
        let data = try decode(GHRepoQueryData.self, json: json)
        let tasks = try #require(ResponseMapping.mapRepoData(data, repoFullName: "acme/widget", ghUser: "danseely"))
        #expect(tasks[0].source == "issue")
        #expect(tasks[0].status == "in progress")
    }

    @Test
    func issueWithLinkedPRViaCrossReferencedEventGetsInProgressStatus() throws {
        let json = #"""
        {
          "data": {
            "repository": {
              "isArchived": false,
              "openIssues": {
                "nodes": [{
                  "number": 1, "title": "T", "url": "https://example/issues/1",
                  "state": "OPEN", "createdAt": "2026-05-01T00:00:00Z",
                  "labels": {"nodes": []},
                  "timelineItems": {
                    "nodes": [{"source": {"url": "https://example/pr/9"}}]
                  }
                }]
              },
              "closedIssues": {"nodes": []},
              "authoredPRs": {"nodes": []},
              "mergedPRs": {"nodes": []},
              "closedPRs": {"nodes": []}
            }
          }
        }
        """#
        let data = try decode(GHRepoQueryData.self, json: json)
        let tasks = try #require(ResponseMapping.mapRepoData(data, repoFullName: "acme/widget", ghUser: "danseely"))
        #expect(tasks[0].status == "in progress")
    }

    @Test
    func issueWithEmptyTimelineGetsOpenStatus() throws {
        let json = #"""
        {
          "data": {
            "repository": {
              "isArchived": false,
              "openIssues": {
                "nodes": [{
                  "number": 1, "title": "T", "url": "https://example/issues/1",
                  "state": "OPEN", "createdAt": "2026-05-01T00:00:00Z",
                  "labels": {"nodes": []},
                  "timelineItems": {"nodes": []}
                }]
              },
              "closedIssues": {"nodes": []},
              "authoredPRs": {"nodes": []},
              "mergedPRs": {"nodes": []},
              "closedPRs": {"nodes": []}
            }
          }
        }
        """#
        let data = try decode(GHRepoQueryData.self, json: json)
        let tasks = try #require(ResponseMapping.mapRepoData(data, repoFullName: "acme/widget", ghUser: "danseely"))
        #expect(tasks[0].status == "open")
    }

    // MARK: - Tag encoding

    @Test
    func tagEncodingMatchesPythonJSONShape() {
        let encoded = ResponseMapping.encodeTags(["bug", "ui"])
        // Both `["bug","ui"]` (compact) and `["bug", "ui"]` (Python default) decode to
        // the same list. We emit compact; downstream just stores the string.
        #expect(encoded == #"["bug","ui"]"#)
    }

    @Test
    func emptyLabelsProduceNoTagsField() throws {
        let json = #"""
        {
          "data": {
            "repository": {
              "isArchived": false,
              "openIssues": {
                "nodes": [{
                  "number": 1, "title": "T", "url": "https://example/issues/1",
                  "state": "OPEN", "createdAt": "2026-05-01T00:00:00Z",
                  "labels": {"nodes": []},
                  "timelineItems": {"nodes": []}
                }]
              },
              "closedIssues": {"nodes": []},
              "authoredPRs": {"nodes": []},
              "mergedPRs": {"nodes": []},
              "closedPRs": {"nodes": []}
            }
          }
        }
        """#
        let data = try decode(GHRepoQueryData.self, json: json)
        let tasks = try #require(ResponseMapping.mapRepoData(data, repoFullName: "acme/widget", ghUser: "danseely"))
        #expect(tasks[0].tags == nil)
        #expect(!tasks[0].presentFields.contains(.tags))
    }

    // MARK: - Fixture decoding helpers

    private func decodeRepo(_ fixtureName: String) throws -> GHRepoQueryData {
        try decodeEnvelope(fixtureName, payload: GHRepoQueryData.self)
    }

    private func decodeReview(_ fixtureName: String) throws -> GHReviewQueryData {
        try decodeEnvelope(fixtureName, payload: GHReviewQueryData.self)
    }

    /// Loads either a colocated fixture (this target's Resources) or falls
    /// back to inline JSON for ad-hoc cases.
    private func decodeEnvelope<T: Decodable & Sendable>(_ name: String, payload: T.Type) throws -> T {
        // Use the inline JSON variants below; happy-path fixtures are embedded
        // as constants to keep AgendumSyncTests independent from AgendumGitHubTests
        // resources.
        let json: String
        switch name {
        case "repoQueryHappyPath_acme_widget":
            json = Self.repoQueryHappyPath
        case "reviewQueryHappyPath_acme_widget_1234":
            json = Self.reviewQueryHappyPath
        default:
            throw FixtureError.notFound(name)
        }
        return try decode(T.self, json: json)
    }

    private func decode<T: Decodable & Sendable>(_ type: T.Type, json: String) throws -> T {
        let data = Data(json.utf8)
        let envelope = try JSONDecoder().decode(GHGraphQLResponse<T>.self, from: data)
        guard let payload = envelope.data else {
            throw FixtureError.envelopeHadNoData
        }
        return payload
    }

    enum FixtureError: Error { case notFound(String); case envelopeHadNoData }

    // Inline copies of the AgendumGitHubTests fixtures so this target stays
    // self-contained. Keep in sync if the originals change.
    private static let repoQueryHappyPath = #"""
    {
      "data": {
        "repository": {
          "isArchived": false,
          "openIssues": {
            "nodes": [
              {
                "number": 42,
                "title": "Bug: nav drawer flickers",
                "url": "https://github.com/acme/widget/issues/42",
                "state": "OPEN",
                "createdAt": "2026-05-01T10:00:00Z",
                "labels": { "nodes": [{"name": "bug"}, {"name": "ui"}] },
                "timelineItems": {
                  "nodes": [
                    {"subject": {"url": "https://github.com/acme/widget/pull/99"}}
                  ]
                }
              }
            ]
          },
          "closedIssues": {
            "nodes": [
              {"number": 30, "url": "https://github.com/acme/widget/issues/30", "state": "CLOSED"}
            ]
          },
          "authoredPRs": {
            "nodes": [
              {
                "number": 99,
                "title": "Fix nav drawer flicker",
                "url": "https://github.com/acme/widget/pull/99",
                "state": "OPEN",
                "isDraft": false,
                "createdAt": "2026-05-05T12:00:00Z",
                "headRefName": "fix-nav-drawer",
                "author": {"login": "danseely"},
                "reviewDecision": null,
                "reviewRequests": {"totalCount": 2},
                "commits": {
                  "nodes": [
                    {"commit": {"committedDate": "2026-05-06T09:30:00Z"}}
                  ]
                },
                "reviews": {
                  "nodes": [
                    {
                      "id": "REVIEW_1",
                      "state": "COMMENTED",
                      "submittedAt": "2026-05-05T15:00:00Z",
                      "author": {"login": "octocat"}
                    }
                  ]
                },
                "reviewThreads": {
                  "nodes": [
                    {
                      "isResolved": false,
                      "isOutdated": false,
                      "comments": {
                        "nodes": [
                          {
                            "createdAt": "2026-05-05T15:00:00Z",
                            "pullRequestReview": {"id": "REVIEW_1"},
                            "author": {"login": "octocat"}
                          }
                        ]
                      }
                    }
                  ]
                },
                "labels": {"nodes": [{"name": "frontend"}]}
              }
            ]
          },
          "mergedPRs": {
            "nodes": [
              {"number": 88, "url": "https://github.com/acme/widget/pull/88", "state": "MERGED", "author": {"login": "danseely"}}
            ]
          },
          "closedPRs": {
            "nodes": [
              {"number": 77, "url": "https://github.com/acme/widget/pull/77", "state": "CLOSED", "author": {"login": "danseely"}}
            ]
          }
        }
      }
    }
    """#

    private static let reviewQueryHappyPath = #"""
    {
      "data": {
        "repository": {
          "pullRequest": {
            "number": 1234,
            "title": "Improve search",
            "url": "https://github.com/acme/widget/pull/1234",
            "state": "OPEN",
            "createdAt": "2026-05-01T08:00:00Z",
            "isDraft": false,
            "headRefName": "improve-search",
            "author": {"login": "octocat", "name": "Octo Cat"},
            "commits": {
              "nodes": [
                {"commit": {"committedDate": "2026-05-09T07:00:00Z"}}
              ]
            },
            "reviews": {
              "nodes": [
                {"author": {"login": "danseely"}, "submittedAt": "2026-05-08T17:00:00Z", "state": "COMMENTED"}
              ]
            },
            "timelineItems": {
              "nodes": [
                {"createdAt": "2026-05-09T06:00:00Z", "requestedReviewer": {"login": "danseely"}}
              ]
            }
          }
        }
      }
    }
    """#
}
