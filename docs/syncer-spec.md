# Syncer Spec

Behavior contract for the Swift port of `../agendum/src/agendum/syncer.py` and its direct dependencies (`gh.py`, `gh_review.py`, `db.py`, `task_api.py`, `config.py`). Source of truth: the original CLI in `../agendum/src/agendum/`, NOT the vendored fork in `Backend/agendum_engine/` (which has accumulated mac-specific complexity that is out of scope per the 2026-05-09 plan revision).

This document defines what the Swift sync engine must do. Tests written against this spec are the primary parity oracle for S3 (the syncer port). The Python source is the secondary oracle, used as a tiebreaker when the spec is ambiguous.

---

## 1. Scope & goals

**The sync engine's job:** for each refresh tick, discover the user's relevant GitHub items (authored PRs, review-requested PRs, assigned issues), compare them against the local SQLite store, and apply create/update/close operations so the dashboard list stays current. Surface "attention" when something newly needs the user's eyes.

**Out of scope for the engine itself:**
- Rendering (lives in `BackendStatusModel` + SwiftUI views)
- User-initiated mutations: `markSeen`, `markReviewed`, status transitions, manual create/remove (live in `TaskStore`, called directly from view actions, NOT routed through the syncer)
- Workspace switching / multi-workspace machinery (MVP cut — see §10)
- Live ad-hoc PR review queries (`gh_review.py`) — used only by the MCP server in the CLI; out of MVP scope

**Engine inputs:**
- A single `AgendumConfig` struct: `orgs: [String]`, `repos: [String]`, `excludeRepos: [String]` (sync-interval and seen-delay live elsewhere; the engine itself is one-shot per call).
- A SQLite DB path (the existing `tasks` table, schema preserved 1:1 — see §2).
- A GitHub auth context (for MVP: the user's `gh auth status` token).

**Engine output:**
```swift
struct SyncResult {
    let changes: Int            // count of rows created/updated/closed
    let hasAttentionItems: Bool // surface a badge / notification
    let error: String?          // nil on success; string on auth/total failure
}
```

The engine is idempotent: running it twice in a row with no GitHub-side change MUST yield `changes == 0` (modulo `updated_at` timestamps written by the diff layer).

---

## 2. Data model

### Schema (`db.py:8-26`)

```sql
CREATE TABLE tasks (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT NOT NULL,
    source TEXT NOT NULL,           -- "pr_authored" | "pr_review" | "issue" | "manual"
    status TEXT NOT NULL,           -- see status vocabulary below
    project TEXT,                   -- short repo name; nil for manual
    gh_repo TEXT,                   -- "owner/name"; nil for manual
    gh_url TEXT UNIQUE,             -- canonical github.com URL; nil for manual
    gh_number INTEGER,
    gh_author TEXT,                 -- login of pr/issue creator (for pr_review only currently)
    gh_author_name TEXT,            -- first-name display (for pr_review only currently)
    tags TEXT,                      -- JSON-encoded array of label names
    seen INTEGER DEFAULT 1,         -- 0 = unseen (red), 1 = seen
    last_changed_at TEXT,           -- ISO8601 of last sync-driven content change
    last_seen_at TEXT,              -- ISO8601 of last user mark-seen
    created_at TEXT,                -- ISO8601 row insert
    updated_at TEXT                 -- ISO8601 of any column write (set by every UPDATE)
);
```

Already shipped 1:1 in Swift via `AgendumMacStore.DatabaseSchema`. No changes here.

### Source vocabulary

| `source` | Origin |
|---|---|
| `pr_authored` | PR where the user is the author. Discovered per-repo via GraphQL. |
| `pr_review` | PR where the user's review is requested. Discovered org-wide via search. |
| `issue` | Issue assigned to the user. Discovered per-repo via GraphQL. |
| `manual` | User-created task in the app. Never touched by sync. |

### Status vocabulary

Pure derivation lives in `gh.derive_*_pr_status` / `gh.derive_issue_status` — already ported to Swift in B2 (`AgendumBackend.GitHubStatusDerivation`). The full set of values the engine writes:

| Status | Source | Meaning |
|---|---|---|
| `merged` | `pr_authored` | PR was merged. **Terminal** — excluded from default list. |
| `closed` | `pr_authored`, `issue` | PR or issue was closed without merge. **Terminal**. |
| `done` | `pr_review` | Review task closed (set when sync drops a review row). **Terminal**. |
| `draft` | `pr_authored` | PR is in draft state. |
| `approved` | `pr_authored` | `reviewDecision == APPROVED`. |
| `changes requested` | `pr_authored` | `reviewDecision == CHANGES_REQUESTED`. |
| `review received` | `pr_authored` | Author has unacknowledged COMMENTED review. See `has_unacknowledged_review_feedback`. |
| `awaiting review` | `pr_authored` | Has open `reviewRequests` and no decision. |
| `open` | `pr_authored`, `issue` | Default open state. |
| `in progress` | `issue` | Open issue has a linked PR (via `CONNECTED_EVENT` / `CROSS_REFERENCED_EVENT`). |
| `review requested` | `pr_review` | User has not yet reviewed. |
| `re-review requested` | `pr_review` | User reviewed but new commits arrived (or explicit re-request). |
| `reviewed` | `pr_review` | User reviewed and no new commits / re-requests. |
| `backlog` | `manual` | Default for new manual tasks. |
| `in progress` | `manual` | User-toggled. |
| `active` | `manual` (legacy) | Migrated to `backlog` on `init_db`. New rows must never write `active`. |

**Terminal set:** `{merged, closed, done}` (`db.TERMINAL_STATUSES`). `get_active_tasks` excludes these by default. Already enforced in Swift via `TaskStore.filterSQL`.

### Tags

JSON-encoded array of label name strings. `pr_review` rows always include the synthetic tag `"review"` (`syncer.py:322`). Other sources include the actual GitHub labels. Stored as `TEXT` in SQL; mapped to `[String]` in Swift `TaskItem` (currently dropped in `TaskItem.init(task:)` — see §10 open question).

### Default ordering (`db.get_active_tasks:84-101`)

```
ORDER BY
    CASE source WHEN 'pr_authored' THEN 1 WHEN 'pr_review' THEN 2
                WHEN 'issue' THEN 3 WHEN 'manual' THEN 4 END,
    seen ASC,
    updated_at DESC
```

Swift currently uses `seen ASC, updated_at DESC, id DESC` (no source-group sort, since the SwiftUI `TaskDisplaySection` re-groups by source at render time). This is an intentional divergence already documented in the C2 review record. **Spec invariant**: the source-group order is a UI concern, not an engine concern.

---

## 3. Sync lifecycle

The engine is a single async function: `runSync(dbPath, config) → SyncResult`. The Python signature is `async def run_sync(db_path: Path, config: AgendumConfig) -> tuple[int, bool, str | None]` (`syncer.py:102`).

### Phases (in order)

**A. Pre-flight (`syncer.py:107-117`)**
1. If `config.orgs` is empty AND `config.repos` is empty → return `(0, false, nil)` immediately. No-op.
2. (Python wraps in `gh.use_gh_config_dir(workspace_gh_dir)`. **MVP cut**: single implicit workspace, single global gh dir.)

**B. Resolve user identity (`syncer.py:126-129`)**
1. `ghUser = await getGitHubUsername()` — REST `GET /user`, return `.login`.
2. If empty → return `(0, false, "gh credentials expired")`.

**C. Resolve target repos (`syncer.py:131-135`)**
1. If `config.repos` is non-empty → use as-is.
2. Else → call `discoverRepos(orgs, ghUser)` (per-org search; see §5.A).
3. Subtract `config.excludeRepos` from the result.

**D. Per-repo fetch (`syncer.py:137-259`)**
- Concurrency: `asyncio.Semaphore(8)`. Swift equivalent: a `TaskGroup` capped at 8 in-flight fetches (or a `Semaphore`-style throttle).
- For each repo, run `fetchRepoData(owner, name, ghUser)` → big GraphQL `REPO_QUERY` (see §5.B).
- If response empty or `repository.isArchived` → skip (do NOT add to `fetchedRepos`).
- Otherwise add `"owner/name"` to `fetchedRepos: Set<String>` and produce up to 5 batches of incoming items per repo:
  - **Authored PRs (open)** — each PR ➝ one `incoming_task` with the derived status (see §3.E.1).
  - **Authored PRs (merged, last 20)** — each ➝ `{title:"", status:"merged", source:"pr_authored", …}`. **Same `author.login.lowercase == ghUser.lowercase` filter as §3.E.1 applies.**
  - **Authored PRs (closed, last 20)** — each ➝ `{title:"", status:"closed", source:"pr_authored", …}`. **Same author filter applies.**
  - **Open issues assigned to user** — each ➝ derived status (see §3.E.2).
  - **Closed issues assigned to user (last 20)** — each ➝ `{title:"", status:"closed", source:"issue", …}`.

**E. Authored-PR enrichment (`syncer.py:153-200`)**
1. Filter the GraphQL `authoredPRs` result by `author.login.lowercase == ghUser.lowercase` (defensive; the org-wide search may surface PRs where the author is technically someone else due to GraphQL filter quirks).
2. Compute `qualifyingReviews`: from `pr.reviews.nodes`, keep those where `author.login != ghUser` AND `submittedAt != nil` AND `id != nil` AND `state ∉ {APPROVED, CHANGES_REQUESTED, PENDING}` (i.e., COMMENTED reviews from others). **Note**: Python uses `state not in (…)` which evaluates true for null `state`. GitHub always returns a state in practice, but a strict Swift port should not require `state` to be non-null — match Python's permissive behavior.
3. `latestCommentReview` = max(`qualifyingReviews`, by `submittedAt`).
4. `latestCommitTime` = `pr.commits.nodes[0].commit.committedDate` (single most recent commit).
5. Call `deriveAuthoredPRStatus(...)` — already in Swift via B2.
6. Tags = `[label.name for label in pr.labels.nodes]`, JSON-encoded.

**F. Issue enrichment (`syncer.py:229-246`)**
1. `hasLinkedPR` = any node in `issue.timelineItems.nodes` whose `subject.url` (ConnectedEvent) or `source.url` (CrossReferencedEvent) is set.
2. `deriveIssueStatus(state, hasLinkedPR)` — already in Swift.
3. Tags = `[label.name for label in issue.labels.nodes]`, JSON-encoded.

**G. Review-PR fetch (`syncer.py:261-323`)**
1. `(reviewPRs, reviewFetchOK) = discoverReviewPRs(orgs, ghUser)` — per-org search via `gh search prs --review-requested` (see §5.A).
2. If `config.repos.isNotEmpty && config.orgs.isEmpty` → set `reviewFetchOK = false` (repo-only workspaces have no scoped review discovery, so we can't trust completeness).
3. For each `prInfo`:
   - Skip if `repo ∈ config.excludeRepos`.
   - Skip if `config.repos.isNotEmpty && repo ∉ config.repos`.
   - Call `fetchReviewDetail(owner, name, number, ghUser)` → `REVIEW_QUERY`.
   - Compute `userReviews` = reviews where `author.login.lowercase == ghUser.lowercase`.
   - `userHasReviewed = userReviews.isNotEmpty`.
   - If reviewed:
     - `lastReviewTime` = max `submittedAt` of `userReviews`.
     - `lastCommitTime` = `pr.commits.nodes[0].commit.committedDate`.
     - `newCommitsSince = lastCommitTime > lastReviewTime`.
     - `reRequestedAfterReview` = iterate `pr.timelineItems.nodes` and check, for each node, `((node.requestedReviewer ?? {}).login ?? "").lowercase == ghUser.lowercase` AND `(node.createdAt ?? "") > lastReviewTime`. The `REVIEW_QUERY` already filters `timelineItems` by `itemTypes: [REVIEW_REQUESTED_EVENT]` so non-matching node types should not appear, but the Python code uses defensive nullish access; the Swift port should do the same.
   - Status = `deriveReviewPRStatus(userHasReviewed, newCommitsSince, reRequestedAfterReview)` — already in Swift.
   - Append incoming task with `source: "pr_review"`, `gh_author = pr.author.login`, `gh_author_name = parseAuthorFirstName(pr.author.name) ?? gh_author`, `tags: ["review"]` (JSON-encoded).

**H. Diff (`syncer.py:330-335`)**
1. `existing = getActiveTasks(dbPath)` — all non-terminal rows.
2. `diff = diffTasks(existing, incomingTasks, fetchedRepos: fetchedRepos, reviewFetchOK: reviewFetchOK)` — see §4.

**I. Apply diff (`syncer.py:337-395`)**
- `now = ISO8601(datetime.utcnow().withMicroseconds())` — single `now` shared across all writes in this sync cycle.
- For each `to_create` item:
  - If `item.status ∈ TERMINAL_STATUSES`: try `findTaskByGhURL`; if found, `updateTask(id, status: terminalStatus)` and `changes += 1`. Otherwise skip (do not create a row in a terminal state).
  - Else if a row exists at that `gh_url` (race: row was created since `getActiveTasks` ran): build `updateFields` from the **fixed allow-list** `{title, source, status, project, gh_repo, gh_number, gh_author, gh_author_name, tags}`, keeping only keys whose incoming value is **not nil** (`item.get(k) is not None`). Then add `seen=0, last_changed_at=now` and call `updateTask(id, **updateFields)`. `changes += 1`. **Note:** `gh_url` is NOT in the allow-list (the row is identified by it; cannot mutate). Sparse incoming dicts (e.g., bare merged/closed payloads) only touch present keys.
  - Else: `addTask(...)`. `changes += 1`.
  - Attention: if `source == "pr_review"` AND `status ∈ {"review requested", "re-review requested"}`, set `attention = true`.
- For each `to_update` item:
  - Python pops `id` from the dict (`task_id = item.pop("id")`) and then calls `updateTask(task_id, **item, seen=0, last_changed_at=now)`. The dict is mutated in place — parity tests that observe the post-apply shape of the `to_update` dict will see `id` removed and `seen`/`last_changed_at` added. Swift port can keep `id` immutable in the equivalent struct; behavior of the resulting SQL UPDATE is what matters.
  - `changes += 1`.
  - Attention: if `"status" in changesDict` AND `status ∈ {"changes requested", "approved", "review received", "re-review requested"}`, set `attention = true`.
- For each `to_close` item:
  - Choose terminal: `merged` if `source == "pr_authored"`, `done` if `source == "pr_review"`, else `closed`.
  - `updateTask(id, status: terminal)`. `changes += 1`. (No `seen` reset on close; not user-actionable.)

**J. Notification overlay (`syncer.py:397-416`)**
1. `notifications = await fetchNotifications(ghUser)` — REST `GET /notifications?all=false` (unread only).
2. For each notification with `reason ∈ {"mention", "comment", "review_requested"}`:
   - Pull `subject.url`. The rewriting is **asymmetric**:
     - If `subject.url` contains `/pulls/`: rewrite `api.github.com/repos` → `github.com` AND `/pulls/` → `/pull/` (singular).
     - If `subject.url` contains `/issues/`: rewrite ONLY `api.github.com/repos` → `github.com`. Do NOT touch the `/issues/` path segment (the API and web URLs already agree on `/issues/`).
     - Otherwise: skip the notification.
   - `findTaskByGhURL(rewrittenURL)`. If found AND `task.seen == 1`:
     - `updateTask(id, seen: 0, last_changed_at: now)`.
     - `changes += 1`. `attention = true`.
   - If `task.seen == 0` already, no-op (don't double-touch `last_changed_at`).

**K. Return** `SyncResult(changes, attention, error: nil)`.

---

## 4. Diff algorithm (`syncer.diff_tasks:32-99`)

Pure function. Inputs:
- `existing: [Task]` — current non-terminal DB rows.
- `incoming: [TaskDict]` — newly fetched items.
- `fetchedRepos: Set<String>?` — repos that responded to GraphQL with non-archived data. Optional.
- `reviewFetchOK: Bool` — false if any review-discovery search returned empty for any org.

Output:
```swift
struct SyncDiff {
    var toCreate: [TaskDict]   // not in DB; insert
    var toUpdate: [PartialUpdate]  // in DB, fields changed
    var toClose: [Task]        // in DB, not in incoming, eligible for close
}
```

### Match index
Build `existingByURL: [String: Task]` keyed by `gh_url` (skip rows without a `gh_url`, i.e., manual tasks).

### For each incoming item
- `incomingURLs.insert(item.gh_url)`.
- If `gh_url` in `existingByURL`:
  - Compare `status` and `title` **unconditionally** (Python checks them with `if old.get(...) != item.get(...)` — no `if key in item` gate). If they differ → write them.
  - Compare `gh_author`, `gh_author_name`, `tags`, `project` **only if the key is present** in the incoming dict (Python uses `if key in item and old.get(key) != item.get(key)`). Sparse incoming dicts (e.g., bare merged/closed payloads carrying only `title`/`status`/`source`/`gh_url`/`gh_number`/`project`/`gh_repo`) leave the un-present keys alone.
  - If anything differs → `toUpdate.append({id: existing.id, ...changedFields})`.
  - **Important behavior**: bare merged/closed payloads carry `title=""`. On the open→merged transition (a previously-stored authored PR with a real title becomes merged), the diff WILL include `title=""` and the apply layer overwrites the stored title with `""`. This is intentional in Python: the row is going terminal and won't be shown in the active list. A Swift port that "preserves" titles on terminal transitions would diverge.
- Else → `toCreate.append(item)`.

### For each existing item
Compute close eligibility (Python `syncer.py:83-97` checks these in this order; all guards are AND-combined so order doesn't affect outcome, but matching the source order keeps the parity test obvious):
1. If row has no `gh_url` → skip (manual or malformed).
2. If `gh_url` is in `incomingURLs` → not closing.
3. If `source == "manual"` → never close from sync.
4. **Review fetch incomplete guard**: if `!reviewFetchOK && source == "pr_review"` → skip. *(If review discovery returned empty for any org, the result set may be incomplete; do not close review rows on incomplete evidence.)*
5. **Partial fetch guard**: if `fetchedRepos != nil && source != "pr_review" && task.gh_repo ∉ fetchedRepos` → skip.
   - Rationale: the row's repo wasn't fetched this cycle, so we don't have evidence the upstream item went away. Could be a transient API failure.
   - **`pr_review` is exempt from THIS guard** (gated by step 4 instead): GitHub may have removed the user from `--review-requested`, so the row's repo is absent from `fetchedRepos` by design. As long as `reviewFetchOK == true`, a `pr_review` row whose repo is missing from `fetchedRepos` is still eligible to close.
6. Else → `toClose.append(task)`.

---

## 5. GitHub data layer

### A. Repo discovery (`gh.discover_repos:517-566`)

Per org, run three `gh search` calls:
- `gh search prs --author $ghUser --owner $org --state open --json repository --limit 200`
- `gh search issues --assignee $ghUser --owner $org --state open --json repository --limit 200`
- `gh search prs --review-requested $ghUser --owner $org --state open --json repository --limit 200`

Union the `repository.nameWithOwner` values across all three calls and all orgs. Used only when `config.repos` is empty.

**Swift port note**: instead of shelling out to `gh search`, use the GitHub Search API REST endpoint directly via URLSession with the gh-derived bearer token. Same query syntax (`is:pr is:open author:$user org:$org`).

### B. Per-repo GraphQL (`gh.REPO_QUERY:363-444`)

Single big query per repo. Fetches in one round-trip:
- `isArchived`
- `openIssues` (first 50, assignee filter): number, title, url, state, createdAt, labels (first 10), timelineItems (last 20, types: CONNECTED_EVENT, CROSS_REFERENCED_EVENT)
- `closedIssues` (first 20, assignee filter, ordered updated DESC): number, url, state
- `authoredPRs` (first 50, open, ordered updated DESC): number, title, url, state, isDraft, createdAt, headRefName, author.login, reviewDecision, reviewRequests.totalCount, last commit committedDate, reviews (last 20: id, state, submittedAt, author.login), reviewThreads (last 50: isResolved, isOutdated, comments [last 20: createdAt, pullRequestReview.id, author.login]), labels (first 10)
- `mergedPRs` (first 20, ordered updated DESC): number, url, state, author.login
- `closedPRs` (first 20, ordered updated DESC): number, url, state, author.login

**Swift port note**: ship the query as a Swift string constant; send via `URLSession` POST to `https://api.github.com/graphql`. Bearer token from `gh auth token`. JSON body: `{"query": …, "variables": {"owner": …, "name": …, "user": …}}`.

### C. Review discovery (`gh.discover_review_prs:569-590`)

Per org: `gh search prs --review-requested $ghUser --owner $org --state open --json number,title,url,repository,author --limit 200`. Returns `(prs, ok)` where `ok = false` if any org call returned empty stdout. **`ok = false` propagates to `reviewFetchOK` and prevents pr_review row closure (see §4 step 4).**

### D. Per-PR review detail (`gh.REVIEW_QUERY:446-475`)

For each review-requested PR, fetch full review history + timeline (last 50 ReviewRequestedEvents). Used to compute `userHasReviewed`, `newCommitsSince`, `reRequestedAfterReview` (see §3.G).

### E. Notifications (`gh.fetch_notifications:593-605`)

REST: `gh api notifications --method GET -f all=false`. Equivalent: `GET /notifications?all=false` with `Accept: application/vnd.github+json`.

### F. Auth

For MVP, the engine assumes the user has a working `gh` CLI session and reads the token via `gh auth token` (or equivalent). No native OAuth in scope. Out-of-band recovery (token expired, missing scopes) surfaces as `error: "gh credentials expired"` from `getGitHubUsername`.

---

## 6. Attention rules (consolidated from §3.I and §3.J)

`hasAttentionItems = true` if any of:

1. **New `pr_review` task created or updated** with status `∈ {"review requested", "re-review requested"}`.
2. **Existing task updated** with status changing to `∈ {"changes requested", "approved", "review received", "re-review requested"}`.
3. **Notification overlay** flipped a previously-seen task to unseen.

`changes` is a count of every row touched (created, updated, closed, or notification-flipped). The two are independent — a sync can have `changes > 0, attention == false` (e.g., new merged PRs only).

---

## 7. Concurrency & isolation

- **Per-repo fetches**: parallel, max 8 in flight (`asyncio.Semaphore(8)`).
- **Review discovery**: serial across orgs.
- **Per-PR review detail**: serial after review discovery completes (Python iterates with `await` in a loop).
- **DB writes**: serial (single `sqlite3.Connection` opened per write call). Swift equivalent: route all writes through the `TaskStore` actor.
- **Single sync cycle**: one cycle from start to finish per call. No background scheduling logic in the engine itself.

---

## 8. Idempotency invariants

A second consecutive `runSync` call with no GitHub-side change MUST satisfy:
- `result.changes == 0`.
- No row's `last_changed_at` has been overwritten.
- No row's `seen` value has flipped.
- No row has been added or closed.

(`updated_at` is set on every `UPDATE tasks ...` because `db.update_task` always appends `updated_at = NOW` (`db.py:117-118`). On a true no-op sync, however, the engine does NOT call `update_task` at all: `diff_tasks` returns empty `to_create` / `to_update` / `to_close` lists, the apply loops in `syncer.py:341-395` execute zero iterations, and notification overlay only writes if a matching row had `seen == 1` AND a relevant unread notification exists. Therefore on a true idempotent run, `updated_at` is preserved. If `updated_at` mutates on a no-op sync, the diff layer or notification overlay has a bug.)

This is the strongest correctness test the parity oracle gives us. S3 must include an idempotency test.

---

## 9. Parity-test fixtures (deliverables for S3)

### Pure functions (already covered by B2, extend as needed)
- `derive_authored_pr_status` — fixtures already in `Tests/AgendumBackendTests/Fixtures/`.
- `derive_review_pr_status`, `derive_issue_status`, `parse_author_first_name`, `extract_repo_short_name`, `has_unacknowledged_review_feedback`.

### Diff (`diff_tasks`)
Recorded JSON fixtures of `(existing, incoming, fetchedRepos, reviewFetchOK) → SyncDiff`. Cases to cover:
1. Empty existing + non-empty incoming → all toCreate.
2. Non-empty existing + identical incoming → no diff.
3. Existing with terminal-status incoming → status update via toCreate path (the "found via gh_url, update status" branch).
4. Existing PR no longer in incoming, repo in `fetchedRepos` → toClose with `merged` for `pr_authored`.
5. Existing PR no longer in incoming, repo NOT in `fetchedRepos` → skipped (partial fetch guard).
6. Existing `pr_review` no longer in incoming, `reviewFetchOK == false` → skipped.
7. Existing `pr_review` no longer in incoming, `reviewFetchOK == true`, repo NOT in `fetchedRepos` → toClose with `done` (review exemption from fetched_repos guard).
8. Manual task → never closed.
9. Update with sparse incoming dict (only `status` present) → only `status` enters toUpdate; `title`/`tags`/etc. untouched.
10. Update where `tags` JSON differs → toUpdate includes `tags`.
11. Existing authored PR with `title="My real title"`; incoming bare merged payload `{title:"", status:"merged", source:"pr_authored", gh_url, gh_number, project, gh_repo}` → toUpdate includes BOTH `title=""` AND `status="merged"` (status and title are unconditionally compared and written; the empty title is intentional).
12. Existing authored PR with `title="My real title"`, `gh_author="me"`; incoming sparse update with only `status="approved"` → toUpdate includes only `status`; `title` and `gh_author` are NOT overwritten (sparse-gated keys).

### Apply layer
End-to-end SQLite round trips against the schema:
1. `to_create` non-terminal → row inserted with `seen=0, last_changed_at=now`.
2. `to_create` terminal where row exists → status updated, no insert.
3. `to_create` terminal where row does NOT exist → no-op.
4. `to_create` race: row already at gh_url at apply time → falls into update branch with `seen=0`.
5. `to_update` → `seen` reset to 0, `last_changed_at = now`, only listed columns mutated.
6. `to_close` for `pr_authored` → status `merged`. For `pr_review` → status `done`. For others → `closed`. `seen` not reset.
7. `to_create` for `pr_review` with `status=review requested` → attention bit set.
8. Notification overlay: REST notification with rewriteable URL → previously-seen task flipped to unseen, attention bit set.
9. Notification overlay: notification URL not in DB → no-op.
10. Notification overlay: matched task already unseen → no-op (no double-count).
11. Notification overlay URL rewriting: `subject.url = "https://api.github.com/repos/owner/name/pulls/42"` → `"https://github.com/owner/name/pull/42"`. `subject.url = "https://api.github.com/repos/owner/name/issues/42"` → `"https://github.com/owner/name/issues/42"` (path unchanged). Asymmetric — pull paths get singularized, issue paths do not.

### End-to-end (with mocked GitHub)
Build a Python parity oracle harness: feed both Python `run_sync` and Swift `runSync` the same canned GraphQL/REST/notification payloads, diff the resulting DB row sets. Drift = test failure. This is the highest-confidence test we can write short of pointing at real GitHub.

---

## 10. MVP cuts and open questions

### MVP cuts (drop from the Swift port)

| Cut | Source | Replaced with |
|---|---|---|
| Multi-workspace machinery | `config.py` | Single implicit workspace at the existing path |
| Per-workspace `gh` config dir isolation | `gh.use_gh_config_dir`, `seed_gh_config_dir`, `recover_gh_auth`, `_TASK_GH_CONFIG_DIR` ContextVar | Use the user's default `gh` auth |
| `auth_login` interactive flow | `gh.auth_login` | `gh auth login` is a user concern; the app can surface an error and a "run `gh auth login`" hint |
| `gh_review.py` (live PR review queries) | Used only by `mcp_server.py` | Out of MVP scope |
| MCP server (`mcp_server.py`) | Used by external integrations | Out of MVP scope |
| Sync interval / scheduling (`config.sync_interval`) | TUI-driven loop in `app.py` | Mac app uses pull-to-refresh + a simple Timer; engine itself is one-shot |
| Display polish: `seen_delay` | `config.seen_delay` | UI concern; lift out of engine config |
| Background daemon mode | `app.py` | Mac app is foreground-only |

### Spec-level open questions (decide during S3 implementation)

1. **`tags` field plumbing.** Schema and engine produce JSON-encoded label arrays; the Swift `TaskItem` currently drops `tags` entirely. Should S3 surface `tags` to the UI, or continue to discard? The CLI's `widgets.py` shows tags. **Recommendation**: surface tags; cheap to plumb through `TaskItem`, makes the dashboard match the CLI more faithfully.

2. **`gh_author` / `gh_author_name` for non-`pr_review` rows.** The current Python populates these only for `pr_review`. The Mac UI shows author for all sources when present. **Recommendation**: keep current behavior (only set for `pr_review`); revisit if the dashboard wants author-by-default.

3. **Concurrent writer.** With Python gone, there is exactly one writer (the Swift `TaskStore` actor). Confirm `DatabaseQueue` (current C2 default) is sufficient and skip the previously-planned switch to `DatabasePool` + WAL config. **Recommendation**: stay on `DatabaseQueue` for MVP.

4. **Notification deduplication.** The Python engine flips `seen=1 → 0` once per notification. If the same notification is fetched again later (same `id`, still unread), it would re-flip. Currently mitigated because the row would already have `seen=0` and the guard `task.get("seen") == 1` prevents the second flip — but `last_changed_at` could oscillate if the user marks seen between sync cycles. **Recommendation**: match Python exactly; if oscillation surfaces in practice, add a notification-id ledger.

5. **Search API rate limits.** Repo discovery runs 3 search queries per org. GitHub's search API is rate-limited at 30 req/min. With > 10 orgs you'd hit it. **Recommendation**: not an MVP concern (single user, single org typical); add throttling if it bites.

6. **Concurrency cap.** Python uses `Semaphore(8)` for repo fetches. Swift `TaskGroup` doesn't have a native semaphore; can achieve the same with a custom async semaphore or by chunking. **Recommendation**: 8 in-flight is fine; implement a simple async semaphore.

7. **Parity oracle lifecycle.** Keep `Backend/agendum_engine/` (or a slimmer `Backend/test-only-python/` snapshot of the original CLI) as a test-only parity oracle through S4. Delete in S4 (the tombstone PR). **Recommendation**: snapshot a clean copy of `../agendum/src/agendum/` into a `Tests/Fixtures/python-oracle/` location in S0 or S3; this is the canonical parity reference, independent of `Backend/agendum_engine/`'s mac-specific drift.

---

## 11. Cross-references

- `../agendum/src/agendum/syncer.py` (419 LOC) — primary source.
- `../agendum/src/agendum/db.py` (151 LOC).
- `../agendum/src/agendum/task_api.py` (175 LOC).
- `../agendum/src/agendum/gh.py` (605 LOC) — status derivation already in Swift via B2.
- `../agendum/src/agendum/gh_review.py` (147 LOC) — out of MVP scope.
- `../agendum/src/agendum/config.py` (213 LOC) — most of which is dropped per §10 MVP cuts.
- `Sources/AgendumMacStore/Schema.swift` — Swift schema (1:1 with §2).
- `Sources/AgendumMacStore/TaskStore.swift` — actor; will gain native add/update/remove paths in S1.
- `Sources/AgendumBackend/GitHubStatusDerivation.swift` — pure status functions already ported (B2).
- `docs/project-state.md` — Speed-Run Sequence (S0–S4).
