from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "Backend" / "agendum_engine"))

from agendum.gh import (  # noqa: E402
    derive_authored_pr_status,
    derive_issue_status,
    derive_review_pr_status,
    extract_repo_short_name,
    has_unacknowledged_review_feedback,
    parse_author_first_name,
)


FIXTURE = REPO_ROOT / "Tests" / "AgendumBackendTests" / "Fixtures" / "GitHubStatusDerivationCases.json"


class GitHubStatusDerivationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.fixture = json.loads(FIXTURE.read_text())

    def test_authored_pull_request_statuses_match_fixture(self) -> None:
        for case in self.fixture["authoredPullRequests"]:
            with self.subTest(case=case["name"]):
                payload = case["input"]
                self.assertEqual(
                    derive_authored_pr_status(
                        is_draft=payload["isDraft"],
                        review_decision=payload["reviewDecision"],
                        state=payload["state"],
                        has_review_requests=payload["hasReviewRequests"],
                        latest_commit_time=payload["latestCommitTime"],
                        latest_comment_review_id=payload["latestCommentReviewID"],
                        latest_comment_review_time=payload["latestCommentReviewTime"],
                        qualifying_reviews=payload["qualifyingReviews"],
                        author_login=payload["authorLogin"],
                        review_threads=self._python_review_threads(payload["reviewThreads"]),
                    ),
                    case["expected"],
                )

    def test_review_pull_request_statuses_match_fixture(self) -> None:
        for case in self.fixture["reviewPullRequests"]:
            with self.subTest(case=case["name"]):
                payload = case["input"]
                self.assertEqual(
                    derive_review_pr_status(
                        user_has_reviewed=payload["userHasReviewed"],
                        new_commits_since_review=payload["newCommitsSinceReview"],
                        re_requested_after_review=payload["reRequestedAfterReview"],
                    ),
                    case["expected"],
                )

    def test_issue_statuses_match_fixture(self) -> None:
        for case in self.fixture["issues"]:
            with self.subTest(case=case["name"]):
                payload = case["input"]
                self.assertEqual(
                    derive_issue_status(
                        state=payload["state"],
                        has_linked_pr=payload["hasLinkedPullRequest"],
                    ),
                    case["expected"],
                )

    def test_review_feedback_flags_match_fixture(self) -> None:
        for case in self.fixture["reviewFeedback"]:
            with self.subTest(case=case["name"]):
                payload = case["input"]
                self.assertEqual(
                    has_unacknowledged_review_feedback(
                        latest_comment_review_id=payload["latestCommentReviewID"],
                        latest_comment_review_time=payload["latestCommentReviewTime"],
                        latest_commit_time=payload["latestCommitTime"],
                        author_login=payload["authorLogin"],
                        qualifying_reviews=payload["qualifyingReviews"],
                        review_threads=self._python_review_threads(payload["reviewThreads"]),
                    ),
                    case["expected"],
                )

    def test_author_first_names_match_fixture(self) -> None:
        for case in self.fixture["authorFirstNames"]:
            with self.subTest(case=case["name"]):
                self.assertEqual(parse_author_first_name(case["displayName"]), case["expected"])

    def test_whitespace_only_author_name_preserves_python_exception(self) -> None:
        with self.assertRaises(IndexError):
            parse_author_first_name("   ")

    def test_repo_short_names_match_fixture(self) -> None:
        for case in self.fixture["repoShortNames"]:
            with self.subTest(case=case["name"]):
                self.assertEqual(extract_repo_short_name(case["fullRepo"]), case["expected"])

    @staticmethod
    def _python_review_threads(review_threads: list[dict[str, Any]]) -> list[dict[str, Any]]:
        converted: list[dict[str, Any]] = []
        for thread in review_threads:
            comments: list[dict[str, Any]] = []
            for comment in thread.get("comments", []):
                python_comment: dict[str, Any] = {
                    "pullRequestReview": {},
                }
                if comment.get("createdAt") is not None:
                    python_comment["createdAt"] = comment["createdAt"]
                if comment.get("authorLogin") is not None:
                    python_comment["author"] = {"login": comment["authorLogin"]}
                if comment.get("pullRequestReviewID") is not None:
                    python_comment["pullRequestReview"] = {"id": comment["pullRequestReviewID"]}
                comments.append(python_comment)
            converted.append(
                {
                    "isResolved": thread.get("isResolved", False),
                    "comments": {
                        "nodes": comments,
                    },
                }
            )
        return converted


if __name__ == "__main__":
    unittest.main()
