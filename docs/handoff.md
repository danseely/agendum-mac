# Handoff

## Current objective
Drive the "standalone Swift app" arc to completion: zero Python at runtime, GRDB-backed Swift data store, Apple-canonical architecture. The arc is structured as three GitHub epics (#24 architecture / #25 backend engine / #26 data store) detailed in `docs/research/synthesis.md`; leaves are filed as their phase approaches, drafts in `docs/research/proposed-issues.md`. The plan-revision binding is in `docs/decisions.md` under "2026-05-03 — Plan revision: standalone Swift app".

## Pause notice (2026-05-04)
Feature work is HALTED at user direction. Phase 1 status: A1 (#27) and A2 (#29) merged into `feature/mac-prototype` (last tip `6ec1fc2`); B1 (#31) implementation complete on `codex/b1-fork-and-vendor` and shipped to PR **#32** (OPEN, ready for review, mergeable=CLEAN, CI `Test` SUCCESS, 0 reviews). The user has not authorized merging PR #32 — do not merge it without explicit approval. No new leaves should be filed or started until the user resumes the autonomous loop.

**Resume sequence (from a fresh agent, after the user says "go"):**
1. `gh pr view 32 --json state,mergeStateStatus,statusCheckRollup` — confirm still OPEN, CLEAN, CI green. Re-run CI on the PR if its head has aged out (`gh pr checks 32 --watch`).
2. Dispatch a `crew:reviewer` subagent for a blind review at ≥75% confidence. The repo's stable bar across recent leaves has been one clean cycle. Lenses to apply: scope discipline (B1 should be ONLY the engine-fork + import-path/CI updates; no behavior changes), license attribution (`Backend/agendum_engine/LICENSE`, README origin SHA), sibling isolation (verify `git grep -nE 'agendum(/src|\.\.\/agendum)' Backend/ Tests/ Scripts/ .github/` returns nothing), and planning-doc consistency.
3. If findings: route fixes back via `crew:builder`; iterate until clean.
4. Merge with `gh pr merge 32 --squash --delete-branch`. Fast-forward local `feature/mac-prototype`.
5. Next leaves: A3 (`@SceneStorage`) on `codex/a3-scenestorage`, B2 (port `gh.py` pure status-derivation functions to Swift) on `codex/b2-status-derivation-port`, or A4/A5/A6 — drafts in `docs/research/proposed-issues.md`. A3 + B2 are both Phase-2 entry points and parallel-safe.

## Probe before acting
Run these first to find the current live state — the handoff snapshot below rots.
- `gh pr view 23` — planning-doc PR. If still open and approvable, review and merge before starting any leaf work. If merged, proceed.
- `gh pr list --state open` — any active leaf-work PRs? If yes, drive the highest-priority one to merge before opening another.
- `gh issue view 24 25 26` — epic state and any newly-filed leaves under them.
- `git fetch --prune && git status` — local sync.
- `git log feature/mac-prototype --oneline -5` — what's actually merged onto the integration branch.

## Branch
The integration branch is `feature/mac-prototype`. Planning-doc work is on `codex/standalone-architecture-planning` (PR #23). All subsequent work goes on `codex/<slug>` branches that PR into `feature/mac-prototype`. Do not push directly to `feature/mac-prototype`.

## Repo state
- A1 leaf PR: **#28** (`codex/a1-observable-migration` → `feature/mac-prototype`), merged 2026-05-03 (squash merge `256678d`).
- A2 leaf PR: **#30** (`codex/a2-os-logger` → `feature/mac-prototype`), merged 2026-05-04 (squash merge `6ec1fc2`).
- B1 leaf PR: **#32** (`codex/b1-fork-and-vendor` → `feature/mac-prototype`), OPEN, ready for review, CI `Test` SUCCESS, 0 reviews. PAUSED awaiting user direction (2026-05-04). URL: `https://github.com/danseely/agendum-mac/pull/32`.
- Planning-doc PR: **#23** (`codex/standalone-architecture-planning` → `feature/mac-prototype`), merged 2026-05-03 (squash merge `3afdb58`).
- Epic tracking issues: **#24** Architecture modernization, **#25** Standalone backend engine, **#26** Native data store. Lifecycle via `gh issue view 24 25 26`.
- Integration branch: `feature/mac-prototype`; PR #21 (item 5 — notifications + dock badge for sync results) merged on 2026-05-03 (squash merge `4172378`).
- Previous checkpoint PR: `https://github.com/danseely/agendum-mac/pull/20`, merged into `feature/mac-prototype` on 2026-05-03 (squash merge `158954c`).
- Earlier checkpoint PR: `https://github.com/danseely/agendum-mac/pull/19`, merged into `feature/mac-prototype` on 2026-05-03 (squash merge `c4a6b5a`).
- Earlier checkpoint PR: `https://github.com/danseely/agendum-mac/pull/18`, merged into `feature/mac-prototype` on 2026-05-03 (squash merge `c29c630`).
- Earlier checkpoint PR: `https://github.com/danseely/agendum-mac/pull/17`, merged into `feature/mac-prototype` on 2026-05-03 (squash merge `c2a6d97`).
- Earlier checkpoint PR: `https://github.com/danseely/agendum-mac/pull/16`, merged into `feature/mac-prototype` on 2026-05-03 (squash merge `12cf468`).
- Earlier checkpoint PR: `https://github.com/danseely/agendum-mac/pull/15`, merged into `feature/mac-prototype` on 2026-05-02 (squash merge `3e4e34a`).
- Earlier checkpoint PR: `https://github.com/danseely/agendum-mac/pull/14`, merged into `feature/mac-prototype` on 2026-05-02 (squash merge `e05efa7`).
- Earlier checkpoint PR: `https://github.com/danseely/agendum-mac/pull/13`, merged into `feature/mac-prototype` on 2026-05-02 (squash merge `30d66d4`).
- Earlier checkpoint PR: `https://github.com/danseely/agendum-mac/pull/12`, merged into `feature/mac-prototype` on 2026-05-02.
- Earlier checkpoint PR: `https://github.com/danseely/agendum-mac/pull/11`, merged into `feature/mac-prototype` on 2026-05-02.
- Earlier checkpoint PR: `https://github.com/danseely/agendum-mac/pull/10`, merged into `feature/mac-prototype` on 2026-05-02.
- Earlier checkpoint PR: `https://github.com/danseely/agendum-mac/pull/9`, merged into `feature/mac-prototype`.
- Workspace selection PR: `https://github.com/danseely/agendum-mac/pull/6`, merged into `feature/mac-prototype` on 2026-05-01.
- Task-list PR: `https://github.com/danseely/agendum-mac/pull/7`, merged into `feature/mac-prototype` on 2026-05-01.
- Post-merge docs update: PR #8 merged into `feature/mac-prototype` on 2026-05-01.
- Remote: `origin` = `git@github.com:danseely/agendum-mac.git`
- Parent PR #2: `https://github.com/danseely/agendum-mac/pull/2`, draft, targeting `main`.
- Earlier merged PRs into `feature/mac-prototype`: #1 (backend helper scaffold), #3 (testing baseline + CI), #4 (branch discipline), #5 (Swift helper-process client).
- Local cleanup: deleted local `codex/test-coverage-reporting`, `feature/backend-helper`, and `codex/document-branch-discipline` branches after merge. The `codex/manual-task-creation` local branch was removed by the PR #11 merge flow; remote PR branches `origin/codex/manual-task-creation` and `origin/codex/swiftui-workflow-coverage` were deleted on the remote. Deleted local `codex/per-task-error-surfacing` after PR #12 merge. Deleted local `codex/structured-error-mapping` after PR #14 merge. Deleted local `codex/packaging-matrix-doc` after PR #15 merge. Remote refs `origin/codex/sync-lifecycle-presentation`, `origin/codex/structured-error-mapping`, `origin/codex/per-task-error-surfacing`, `origin/codex/packaging-matrix-doc`, and `origin/codex/app-bundle-smoke` pruned locally on 2026-05-03 after upstream cleanup.
- Branch discipline: do not push directly to `feature/mac-prototype`; use short-lived branches and PRs targeting `feature/mac-prototype` unless explicitly requested otherwise.
- Engine source: vendored in-tree at `Backend/agendum_engine/agendum/` (forked 2026-05-04 from `danseely/agendum` commit `b62a45c6a28f8ffd4b57a597de4744dc83d0d94d`; see `Backend/agendum_engine/README.md` and the 2026-05-04 B1 entry in `docs/decisions.md`). The sibling-checkout discipline is retired: neither local development, the Python tests, the helper subprocess, `swift run AgendumMac`, nor CI requires `danseely/agendum` to be checked out alongside `agendum-mac`.
- PR #17 (item 1 — open task URL detail action) merged into `feature/mac-prototype` on 2026-05-03 (squash merge `c2a6d97`).
- PR #18 (item 2 — task list filtering UI) merged into `feature/mac-prototype` on 2026-05-03 (squash merge `c29c630`).
- PR #19 (item 3 — settings / auth-repair UI) merged into `feature/mac-prototype` on 2026-05-03 (squash merge `c4a6b5a`).
- PR #20 (item 4 — keyboard shortcuts + menu coverage) merged into `feature/mac-prototype` on 2026-05-03 (squash merge `158954c`).
- PR #21 (item 5 — notifications + dock badge for sync results) merged into `feature/mac-prototype` on 2026-05-03 (squash merge `4172378`).
- Last validation date: 2026-05-03 (A2 — `os.Logger` adoption gate on `codex/a2-os-logger`): `swift build` passed; `swift test --enable-code-coverage` passed with 119 Swift tests (unchanged from post-A1 baseline); `/opt/homebrew/bin/python3 -m unittest discover -s Tests` passed with 61 Python tests; `git diff --check` passed; `git grep -nP '^\s*print\(' -- Sources/` returned no matches.

## Completed
- Created `agendum-mac` outside `../agendum`.
- Added SwiftUI app scaffold in `Sources/AgendumMac/AgendumMacApp.swift`.
- Added Swift Package manifest in `Package.swift`.
- Added planning memory in `docs/plan.md`, `docs/status.md`, and `docs/decisions.md`.
- Added port assessment in `docs/mac-gui-port-evaluation.md`.
- Initialized Git locally.
- Sent plan through two independent agent reviews and incorporated their findings into the planning docs.
- Re-vetted `docs/backend-contract.md`; reviewer returned CLEAN.
- Recorded plan readiness in `docs/status.md` and `docs/decisions.md`.
- Published README-only `main` to `https://github.com/danseely/agendum-mac`.
- Created `feature/mac-prototype` as the broad integration branch for prototype work.
- Pushed `feature/mac-prototype` and opened draft PR #2 against `main`.
- Retargeted backend-helper PR #1 to `feature/mac-prototype`.
- Added `Backend/agendum_backend/helper.py`, a JSON-over-stdio helper that handles protocol validation, `workspace.current`, and `auth.status`.
- Added `Backend/agendum_backend_helper.py` as the helper entrypoint.
- Added `Tests/test_backend_helper.py` coverage for workspace payloads, missing `gh`, authenticated fake `gh`, and protocol errors.
- Rebuilt `feature/backend-helper` as a scoped child branch and retargeted PR #1 to `feature/mac-prototype`.
- Fixed PR review finding: valid JSON non-object requests now return `payload.invalid` instead of crashing.
- Merged PR #1 into `feature/mac-prototype`.
- Added `docs/testing.md` with backend, integration, Swift, UI, and release testing gates.
- Updated `docs/plan.md`, `docs/mac-gui-port-evaluation.md`, `docs/decisions.md`, and `docs/status.md` to treat testing as a milestone gate.
- Planned the immediate test checkpoint around the existing helper commands and process boundary.
- Added `Tests/test_backend_helper_process.py` with subprocess JSONL coverage for the helper entrypoint.
- Expanded `Tests/test_backend_helper.py` with protocol and auth edge-case coverage.
- Added `Scripts/python_coverage.py`, a stdlib-based backend helper coverage reporter.
- Improved helper coverage with unit tests for `run_stdio` and exception envelopes.
- Clarified coverage strategy: temporary Python helper script now, SwiftPM coverage for Swift tests while package-only, and Xcode/`xccov` coverage after an Xcode app project exists.
- Added `.github/workflows/test.yml` to run the current test pipeline in GitHub Actions on macOS.
- Updated the workflow to `actions/checkout@v5` after GitHub warned that `actions/checkout@v4` uses deprecated Node 20.
- Removed the `codex/**` push trigger so PR branch updates do not run duplicate push and pull-request workflows.
- Updated the workflow to run on all pull requests, including future stacked feature sub-PRs, while keeping push runs limited to `main`.
- Merged PR #3 into `feature/mac-prototype`.
- Pulled `feature/mac-prototype` to merge commit `408d800`.
- Deleted local topic branches `codex/test-coverage-reporting` and `feature/backend-helper`.
- PR #4 recorded branch discipline: future updates to `feature/mac-prototype` should land through PRs, not direct pushes.
- Added `AgendumMacCore` in `Sources/AgendumMacCore/BackendClient.swift` with Swift models for `Workspace`, `AuthStatus`, helper error envelopes, and a long-lived JSONL helper process client.
- Updated `Package.swift` to expose `AgendumMacCore` and add `AgendumMacCoreTests`.
- Updated `Sources/AgendumMac/AgendumMacApp.swift` so the sidebar loads `workspace.current` and `auth.status` from the helper and displays workspace/auth state.
- Added `Tests/AgendumMacCoreTests/BackendClientTests.swift` covering real helper process requests, process reuse, helper error mapping, malformed response JSON, mismatched response IDs, unsupported protocol versions, stderr mapping, and request timeout/restart behavior.
- Updated `.github/workflows/test.yml` so CI runs `swift test --enable-code-coverage`.
- Recorded the development runner choice in `docs/decisions.md`: SwiftPM development runs use the checked-out helper and prefer common Homebrew Python paths before `/usr/bin/python3`; production packaging remains undecided.
- Opened draft PR #5 against `feature/mac-prototype`.
- Addressed PR #5 review findings: helper requests now have a bounded timeout path, the helper stdout reader no longer blocks directly on `availableData`, and development helper-root discovery no longer assumes the launch cwd is the repo root.
- PR #5 latest CI run passed after review fixes: `25193185925`.
- Marked PR #5 ready and merged it into `feature/mac-prototype` with squash merge commit `a3c17cf`.
- Pulled `feature/mac-prototype`; it was already up to date after the merge.
- Created `codex/workspace-selection` from updated `feature/mac-prototype`.
- Implemented `workspace.list` in `Backend/agendum_backend/helper.py`; it returns base plus valid namespace directories under `<base>/workspaces` and marks the current helper namespace.
- Implemented `workspace.select` in `Backend/agendum_backend/helper.py`; it validates namespace payloads, creates/loads config with existing agendum config helpers, updates `HelperState.namespace`, returns refreshed auth status, and returns an idle sync status stub without starting sync.
- Added backend tests in `Tests/test_backend_helper.py` for listing, namespace selection, base selection, invalid payloads, and invalid namespace rollback.
- Added subprocess tests in `Tests/test_backend_helper_process.py` for shared-process workspace selection/listing and invalid selection preserving base state.
- Added Swift client types and methods in `Sources/AgendumMacCore/BackendClient.swift` for `listWorkspaces()` and `selectWorkspace(namespace:)`, including explicit `namespace: null` encoding for base selection.
- Added Swift process-boundary coverage in `Tests/AgendumMacCoreTests/BackendClientTests.swift` for selecting/listing workspaces in one helper process.
- Wired `Sources/AgendumMac/AgendumMacApp.swift` so the sidebar status area loads workspace options and switches workspaces through a menu.
- Updated `docs/plan.md`, `docs/status.md`, and `docs/handoff.md` for the workspace selection checkpoint.
- Opened draft PR #6 against `feature/mac-prototype`.
- Addressed PR #6 review finding: `workspace.select` now rejects blank string namespaces so only explicit `namespace: null` selects the base workspace.
- Marked PR #6 ready for review.
- Checked PR #6 on 2026-05-01: open, non-draft, clean merge state, no comments/reviews, and passing `Test` check from run `25194851503`.
- Merged PR #6 into `feature/mac-prototype` with squash merge `f53c62e`.
- Fast-forwarded local `feature/mac-prototype` to `f53c62e`.
- Rebased `codex/task-list-loading` onto `feature/mac-prototype`.
- Created local branch `codex/task-list-loading` from `codex/workspace-selection`.
- Implemented `task.list` in `Backend/agendum_backend/helper.py`; it validates optional filters, initializes the selected workspace DB, calls `agendum.task_api.list_tasks`, and maps task fields to the v0 lower-camel-case bridge payload.
- Added helper error handling for task-storage SQLite failures.
- Added backend unit tests in `Tests/test_backend_helper.py` for task payload mapping, default empty workspace initialization, optional field mapping, filter handling, selected namespace DB usage, and invalid task-list payloads.
- Added subprocess JSONL coverage in `Tests/test_backend_helper_process.py` for `task.list`.
- Added `AgendumTask` plus `listTasks(source:status:project:includeSeen:limit:)` in `Sources/AgendumMacCore/BackendClient.swift`.
- Added Swift client test coverage in `Tests/AgendumMacCoreTests/BackendClientTests.swift` for full task-list request encoding and response decoding.
- Updated `Sources/AgendumMac/AgendumMacApp.swift` so the dashboard task lists and badges load from the backend helper instead of hard-coded sample data; workspace selection reloads tasks.
- Committed task-list loading as `feeee62`.
- Pushed `codex/task-list-loading` to origin.
- Opened draft PR #7 against `feature/mac-prototype`: `https://github.com/danseely/agendum-mac/pull/7`.
- Reviewed PR #7 locally and found cleanup items: stale SwiftUI task state after failed reload, invalid `task.list` payloads touching storage before validation, and stale handoff HEAD metadata.
- Fixed and pushed the first PR #7 review findings in commit `fbe2e57`.
- Ran a fresh blind review of PR #7; it found selected task ID carryover across workspace reloads plus stale planning-doc state.
- Fixed and pushed the second PR #7 review findings in commit `ce6f48c`.
- Ran blind review cycle 1 after `ce6f48c`; it found no code-level bugs/regressions and only stale planning-doc state.
- Updated this handoff to avoid hard-coded HEAD hashes that become stale on every docs-only commit.
- Ran blind review cycle 2 after `810f56f`; it found no code-level bugs/regressions and only next-action drift in planning docs.
- Updated planning next-action wording to describe the active blind-review loop without naming a docs-only commit that becomes stale after push.
- Ran blind review cycle 3 after `4df64c6`; it found no actionable bugs, regressions, missing required tests, or stale project-memory docs.
- Marked PR #7 ready for review.
- Merged PR #7 into `feature/mac-prototype` with squash merge `8e71589`.
- Fast-forwarded local `feature/mac-prototype` to `8e71589`.
- The local `codex/task-list-loading` branch was removed by the merge flow; the remote PR branch was deleted.
- Merged PR #8 into `feature/mac-prototype` with squash merge `42f06aa`.
- Created `codex/task-detail-actions-sync` from updated `feature/mac-prototype`.
- Implemented backend helper support in `Backend/agendum_backend/helper.py` for task detail, status actions, per-task mark seen, removal, sync status, and force sync.
- Added backend tests in `Tests/test_backend_helper.py` and `Tests/test_backend_helper_process.py` for the new commands.
- Added Swift client methods and response payload types in `Sources/AgendumMacCore/BackendClient.swift`.
- Added Swift client coverage in `Tests/AgendumMacCoreTests/BackendClientTests.swift`.
- Wired `Sources/AgendumMac/AgendumMacApp.swift` so the toolbar can force sync, the status panel shows sync state, and the detail pane performs source-aware backend task actions.
- Opened draft PR #9 against `feature/mac-prototype`.
- Checked PR #9 with `gh pr view`; it is open as a draft, mergeable cleanly, and its `Test` check is passing on the current head.
- Ran a focused PR #9 review and fixed two findings:
  - `Backend/agendum_backend/helper.py`: unexpected `run_sync` exceptions now set terminal `error` sync status and return it, instead of leaving `state.sync_status` stuck at `running`.
  - `Sources/AgendumMac/AgendumMacApp.swift`: manual status actions now key off backend source `manual`, so GitHub issue rows grouped under Issues & Manual do not get local manual status controls.
- Ran a fresh blind review of PR #9 and fixed two sync-state findings:
  - `Backend/agendum_backend/helper.py`: `workspace.select` now resets `state.sync_status`, `sync.force` starts a background worker and returns `running` immediately, duplicate force-sync requests return the current running state, and sync completions are token-guarded so stale workers cannot overwrite status after workspace switches.
  - `Sources/AgendumMac/AgendumMacApp.swift`: the force-sync UI path now polls `sync.status` until completion or a bounded timeout before reloading tasks.
  - `Tests/test_backend_helper.py`: coverage now includes async force-sync completion, duplicate running requests, error/exception completion status, and workspace-select sync reset.
- Ran a second fresh blind review of PR #9. It found no code-level bugs or contract regressions, but flagged that `sync.force` process-boundary behavior needed a real subprocess JSONL test because planning docs claimed subprocess coverage.
- Added `Tests/test_backend_helper_process.py` coverage that keeps one helper process alive, sends `sync.force`, then polls `sync.status` over the same JSONL process until completion.
- Ran a third fresh blind review of PR #9 at remote head `f764f9e`; it found no actionable bugs, regressions, contract drift, concurrency issues, missing required tests, or planning-doc drift. Residual risk remains deeper SwiftUI workflow coverage, especially force-sync polling and detail-pane actions.
- Added a concrete SwiftUI workflow coverage checkpoint to `docs/testing.md`. The next coverage step is to extract `BackendStatusModel` or equivalent app workflow state into a testable target, inject a fake backend-client protocol, and cover refresh, workspace switching, force-sync polling, task actions, detail-pane action availability, and toolbar/menu sync convergence without launching the full app.
- Marked PR #9 ready and merged it into `feature/mac-prototype`.
- Fast-forwarded local `feature/mac-prototype` after the PR #9 merge and created `codex/swiftui-workflow-coverage`.
- Added `AgendumMacWorkflow` in `Sources/AgendumMacWorkflow/TaskWorkflowModel.swift`.
- Moved `TaskItem`, `TaskSource`, and `BackendStatusModel` out of `Sources/AgendumMac/AgendumMacApp.swift` into the workflow target.
- Added `AgendumBackendServicing` so workflow tests can inject a fake backend without launching SwiftUI or spawning the Python helper.
- Added pure detail-pane action planning through `TaskItem.availableDetailActions`.
- Wired the app menu `Sync Now` command and toolbar sync button to the same shared `BackendStatusModel.forceSync()` instance.
- Added `Tests/AgendumMacWorkflowTests/TaskWorkflowModelTests.swift` covering refresh success/failure, workspace switching/no-op behavior, force-sync polling, task action reloads, task action failure behavior, and detail-pane action availability.
- Added `TaskDashboardCommands` so toolbar sync and menu sync share the same workflow command path, with fake-backed test coverage.
- Committed the checkpoint as `2b78794` and pushed `codex/swiftui-workflow-coverage`.
- Opened draft PR #10: `https://github.com/danseely/agendum-mac/pull/10`.
- PR #10 GitHub Actions `Test` passed on run `25254571906`.
- Marked PR #10 ready for review.
- PR #10 GitHub Actions `Test` passed on run `25254607730` after the PR-readiness docs follow-up.
- PR #10 GitHub Actions `Test` is passing at the time of this update.
- Addressed PR #10 review feedback: restructured `Tests/AgendumMacWorkflowTests/TaskWorkflowModelTests.swift::testRefreshFailureClearsTasksAndSurfacesError` so a successful refresh populates tasks before the failing refresh proves the catch's clear, and expanded the 2026-05-02 entry in `docs/decisions.md` to name `AgendumBackendServicing` and `TaskDashboardCommands` alongside the `AgendumMacWorkflow` target.
- PR #10 was marked ready, passed GitHub Actions `Test`, and merged into `feature/mac-prototype` on 2026-05-02.
- Fast-forwarded local `feature/mac-prototype` after the PR #10 merge and created `codex/manual-task-creation` from the updated tip.
- Implemented `task.createManual` in `Backend/agendum_backend/helper.py` calling `agendum.task_api.create_manual_task`, with `_required_string`, `_optional_create_string`, and `_optional_tag_list` validation rejecting blank strings, non-string tag entries, and non-list tag values. Empty `project`/`tags` defaults to `null` (using `agendum`'s `manual` source / `backlog` status).
- Added backend unit tests in `Tests/test_backend_helper.py`: persists task and returns payload, minimal payload, namespaced DB usage, and a parametrized invalid-payload coverage table.
- Added subprocess JSONL coverage in `Tests/test_backend_helper_process.py` (`test_task_create_manual_persists_through_jsonl_process`) that creates, lists, and rejects an invalid manual task across one helper process.
- Added `createManualTask(title:project:tags:)` and a `TaskCreateManualRequestPayload` (omits nil project/tags) to `Sources/AgendumMacCore/BackendClient.swift`, plus `testClientCreatesManualTask` in `Tests/AgendumMacCoreTests/BackendClientTests.swift` covering full and minimal request encoding plus response decoding.
- Added the protocol method to `AgendumBackendServicing`, `BackendStatusModel.createManualTask(...)` returning `Bool`, and workflow tests `testCreateManualTaskSucceedsAndReloadsTasks` / `testCreateManualTaskFailureKeepsExistingTasksAndSurfacesError`.
- Wired a SwiftUI "New Task" toolbar button in `Sources/AgendumMac/AgendumMacApp.swift` that opens a `CreateManualTaskSheet` form (title, optional project, comma-separated tags); the sheet dismisses only on success and surfaces failures through `BackendStatusModel.errorMessage`.
- Committed the manual task creation checkpoint as `9a1239f` on `codex/manual-task-creation`.
- Pushed `codex/manual-task-creation` to `origin` and opened draft PR #11: `https://github.com/danseely/agendum-mac/pull/11`.
- PR #11 was marked ready, passed GitHub Actions `Test`, and merged into `feature/mac-prototype` on 2026-05-02 (squash merge `1e8306a`).
- Fast-forwarded local `feature/mac-prototype` to `1e8306a` and created `codex/per-task-error-surfacing` from the updated tip.
- Added `@Published taskActionErrors: [TaskItem.ID: String]` and `errorForTask(id:)` to `BackendStatusModel` in `Sources/AgendumMacWorkflow/TaskWorkflowModel.swift`.
- Reworked `performTaskAction(taskID:_:)` so task-action failures populate the per-task map and successful actions clear only the affected task's entry, leaving the global `errorMessage` for cross-cutting flows (refresh, workspace selection, force sync, manual task creation).
- `refresh()` and `selectWorkspace(...)` now reset `taskActionErrors = [:]` on both success and failure paths.
- Added `actionError: String?` to `TaskDetail` in `Sources/AgendumMac/AgendumMacApp.swift`; the dashboard passes `backendStatus.errorForTask(id: task.id)` and the detail view renders a red caption beneath the action buttons (with `accessibilityIdentifier("task-action-error")`).
- Replaced `testTaskActionFailureLeavesExistingTasksUntouched` with `testTaskActionFailureScopesErrorToTaskAndKeepsGlobalErrorClean` in `Tests/AgendumMacWorkflowTests/TaskWorkflowModelTests.swift`, and added `testTaskActionSuccessClearsExistingPerTaskError`, `testTaskActionFailureOnOneTaskDoesNotClearAnotherTasksError`, `testRefreshClearsTaskActionErrors`, and `testSelectWorkspaceClearsTaskActionErrors`. Also added `taskActionErrors.isEmpty` assertion to `testTaskActionsCallBackendAndReloadTasks`.
- Added `PresentedError` (message + optional recovery + optional code) and `PresentedError.from(_:)` factory to `Sources/AgendumMacWorkflow/TaskWorkflowModel.swift`. Replaced `errorMessage: String?` with `error: PresentedError?` plus a computed `errorMessage` shim, and replaced `taskActionErrors: [TaskItem.ID: String]` with `taskActionErrors: [TaskItem.ID: PresentedError]`. `errorForTask(id:)` now returns `PresentedError?`.
- Added `lastSyncLabel` (relative, `en_US_POSIX`, ISO8601 parsing) and `hasAttentionItems` accessors on `BackendStatusModel`, plus a `now: () -> Date` clock seam on the initializer.
- Updated `syncLabel` to drop the `lastError` mash-up; sync errors continue to flow through `forceSync`'s catch into the structured `error`.
- Added a public initializer on `BackendErrorPayload` so workflow tests can construct payloads outside `AgendumMacCore`.
- Updated `Sources/AgendumMac/AgendumMacApp.swift` `BackendStatusPanel` sync row to render state + an optional "Last synced N min ago" caption + a `Needs attention` indicator, and the global error block to render message + optional recovery on two lines. `TaskDetail.actionError` is now `PresentedError?` and renders the same two-line treatment. Added accessibility identifiers `sync-status-state`, `sync-status-last-synced`, `sync-status-attention-indicator`, `backend-error-message`, `backend-error-recovery`, `task-action-error-recovery`.
- Added workflow tests `testPresentedErrorExtractsHelperPayloadFields`, `testPresentedErrorFallsBackToDescriptionForGenericErrors`, `testRefreshFailureSurfacesStructuredRecoveryHint`, `testTaskActionFailureSurfacesStructuredRecoveryHint`, `testLastSyncLabelFormatsIso8601Timestamp`, `testLastSyncLabelNilWhenNoTimestamp`, `testHasAttentionItemsReflectsSyncStatus`. Updated existing per-task error assertions to compare against `errorForTask(id:)?.message`.
- Item 1 (open task URL): added a `URLOpening` typealias and `openURL` initializer parameter on `BackendStatusModel`, an `openTaskURL(id:)` action that records `client.urlOpenFailed`/`client.taskHasNoURL` per-task errors via the existing `taskActionErrors` map, and `defaultURLOpener` wrapping `NSWorkspace.shared.open`. Replaced the SwiftUI detail-pane `Open in Browser` button with one that routes through `backendStatus.openTaskURL(id:)` and added accessibility identifier `task-action-open-browser`. Added new `AgendumMacWorkflowTests` covering availability, opener invocation, success error-clearing, failure error code, no-URL guard, unknown-task-id no-op, isLoading invariance, refresh/workspace-switch clearing, and per-task error isolation. Drive-by fix to `BackendClientConfiguration.firstAncestor` resolved an infinite-loop bug introduced by PR #16's filesystem-walk variant. PR #17 merged on 2026-05-03 (squash merge `c2a6d97`).
- Item 2 (task list filtering UI): extended `BackendStatusModel` in `Sources/AgendumMacWorkflow/TaskWorkflowModel.swift` with `@Published` filter state for `source`, `status`, `project`, `includeSeen`, and `limit`; routed all filter changes through a single `loadTaskItems` path so filter mutations issue a fresh `task.list` request. Added workspace-switch reset semantics so selecting a different workspace clears filter state to defaults. Surfaced filter controls in the SwiftUI dashboard in `Sources/AgendumMac/AgendumMacApp.swift`. Added fake-backed `AgendumMacWorkflowTests` covering filter routing, defaults, and reset behavior. PR #18 merged on 2026-05-03 (squash merge `c29c630`).
- Item 3 (settings / auth-repair UI): added a new `auth.diagnose` helper command in `Backend/agendum_backend/helper.py` returning `{gh: {found, path, version, installed}, auth, host, helperPath}`, plus `_gh_version`, `_helper_path_entries`, and `_default_gh_host` private helpers. Added `AuthDiagnostics` (with nested `GHDiagnostics`) and `func authDiagnose() async throws -> AuthDiagnostics` to `Sources/AgendumMacCore/BackendClient.swift`, and extended `AuthStatus` with an optional `repairCommand: String?` field populated only in the unauthenticated-with-gh-found branch. Added `@Published diagnostics`/`@Published diagnosticsError` state plus `refreshDiagnostics()`, `copyAuthLoginCommand()`, and `openGHInstallURL()` methods to `BackendStatusModel` in `Sources/AgendumMacWorkflow/TaskWorkflowModel.swift`, with a new `Pasteboarding` typealias and `defaultPasteboard` static (parallel to `URLOpening` / `defaultURLOpener`). Replaced the SwiftUI `SettingsView` stub in `Sources/AgendumMac/AgendumMacApp.swift` with a real diagnostic + remediation form (gh status / auth status / helper PATH / repair instructions / Refresh / Copy login command / Open install page) bound via `@EnvironmentObject`. Added backend, subprocess JSONL, Swift client, and workflow tests covering the new command and the model methods. In-scope drive-by: unified `repairInstructions` (helper.py:439) behind a single shared `_format_repair_command(gh_config_dir)` helper that uses `shlex.quote(...)` so paths with spaces are safe. PR #19 merged on 2026-05-03 (squash merge `c4a6b5a`).
- Item 5 (notifications + dock badge for sync results): added `Notifying` and `BadgeSetting` typealiases plus seam parameters on `BackendStatusModel.init` in `Sources/AgendumMacWorkflow/TaskWorkflowModel.swift`, with `RecordingNotifier` and `RecordingBadgeSetter` test fakes. Exposed an `attentionItemCount` Int accessor and a `setBadgeForAttentionCount()` method that the App layer drives from `.onChange(of: hasAttentionItems)` (single-writer badge rule). Routed `forceSync` to post sync-completion notifications on success, on thrown-error, and on backend-reported error branch (b) via a shared `postSyncCompletedNotification(success:failure:)` helper that uses the shared identifier `agendum.sync.completed`. Added a prime-on-appear `.task` cold-start hedge so the badge is correct before the first sync. Extended the SwiftUI `SettingsView` in `Sources/AgendumMac/AgendumMacApp.swift` with a notification-authorization-status row and an "Enable Notifications" button. Guarded `defaultNotifier` with a `Bundle.main` check so non-app hosts (tests) do not invoke `UNUserNotificationCenter.current()`. Imported `UserNotifications` with `@preconcurrency` (commit `5f54489`) so Swift 6 strict-concurrency CI accepts the framework's pre-Sendable types. PR #21 merged on 2026-05-03 (squash merge `4172378`).
- Item 4 (keyboard shortcuts + menu coverage): extended the `TaskDashboardCommand` enum in `Sources/AgendumMacWorkflow/TaskWorkflowModel.swift` with `newTask`, `openInBrowser`, `markSeen`, `markReviewed`, `markInProgress`, `moveToBacklog`, `markDone`, and `remove` cases plus an `availability(on:)` predicate composing `isLoading` and per-task `availableDetailActions`. Added a `selectedTaskID` mirror seam (`@Published public internal(set) var selectedTaskID: TaskItem.ID?`) plus a `setSelectedTaskID(_:)` setter so `TaskDashboardCommand.perform(on:)` can target the currently-selected task without reaching across modules. Extended the `TaskDashboardCommands` struct with named slots (`menuNewTask`, `menuOpenInBrowser`, etc.). Replaced the single `CommandGroup(after: .appInfo)` block in `Sources/AgendumMac/AgendumMacApp.swift` with a `CommandGroup(replacing: .newItem)` File-menu surface (New Task, Refresh, Sync Now) and a new top-level `CommandMenu("Task")` for the per-task actions, each carrying a `keyboardShortcut(...)` and `accessibilityIdentifier("menu-action-*")`. Lifted the App-level `@State` for `selectedTask` and `isShowingCreateManualTask` from `TaskDashboardView` to `AgendumMacApp` so the `.commands { ... }` closure has lexical access; passes both into the dashboard via `@Binding`. Relocated the Sync Now shortcut from the prior `Cmd-R` to `Cmd-Shift-S` (freeing `Cmd-R` for Refresh, the conventional macOS "reload" shortcut), and chose `Cmd-Shift-Backspace` for Remove (rather than Finder's `Cmd-Backspace`) to avoid menu-vs-TextField key-equivalent collisions when a text field has focus. Added 21 new workflow tests covering the new commands' `perform(on:)` and `availability(on:)` semantics, no-op-when-no-selection behavior, and selection-seam plumbing. PR #20 merged on 2026-05-03 (squash merge `158954c`).

## Validation

### Current baseline (post-PR-#10, expected on `codex/manual-task-creation` before any new code)
- `swift build` passes.
- `swift test --enable-code-coverage` passes: 22 Swift tests (11 `AgendumMacCoreTests` + 11 `AgendumMacWorkflowTests`).
- `/opt/homebrew/bin/python3 -m unittest discover -s Tests` passes: 43 tests.
- `/opt/homebrew/bin/python3 Scripts/python_coverage.py` passes: 416/455 lines (91.4%) for `Backend/agendum_backend/helper.py`.
- `git diff --check` passes.
- `swift run AgendumMac` launches without an immediate startup crash.
- Note: `python3` resolves to pyenv 3.10.2 in the user shell, which lacks `tomllib`; use `/opt/homebrew/bin/python3` for local helper tests. CI uses macOS system Python and is unaffected.

### Manual task creation checkpoint (on `codex/manual-task-creation`, after the changes listed under Completed)
- `swift build` passes.
- `swift test --enable-code-coverage` passes: 25 Swift tests (12 `AgendumMacCoreTests` + 13 `AgendumMacWorkflowTests`).
- `/opt/homebrew/bin/python3 -m unittest discover -s Tests` passes: 48 tests.
- `/opt/homebrew/bin/python3 Scripts/python_coverage.py` passes: 464/505 lines (91.9%) for `Backend/agendum_backend/helper.py`.
- `git diff --check` passes.
- `swift run AgendumMac` launches without an immediate startup crash (smoke run held open ~4s before manual termination).

### Sync lifecycle and structured error presentation checkpoint (on `codex/sync-lifecycle-presentation`, after the changes listed under Completed)
- `swift build` passes.
- `swift test --enable-code-coverage` passes: 36 Swift tests (12 `AgendumMacCoreTests` + 24 `AgendumMacWorkflowTests`).
- `/opt/homebrew/bin/python3 -m unittest discover -s Tests` passes: 48 tests.
- `/opt/homebrew/bin/python3 Scripts/python_coverage.py` passes: 464/505 lines (91.9%) for `Backend/agendum_backend/helper.py` (no backend changes in this checkpoint).
- `git diff --check` passes.
- `swift run AgendumMac` launches without an immediate startup crash (smoke run held open ~5s before SIGTERM, exit code 143).
- Blind review fix landed (locale seam injected on `BackendStatusModel.init` so `RelativeDateTimeFormatter` follows the user's macOS locale in production while tests pin `en_US_POSIX`; `testLastSyncLabelFormatsIso8601Timestamp` now also asserts the `"ago"` direction): `swift build` passed, `swift test --enable-code-coverage` passed (36 Swift tests), `/opt/homebrew/bin/python3 -m unittest discover -s Tests` passed (48 tests), and `git diff --check` passed.

### Structured error mapping checkpoint (on `codex/structured-error-mapping`, after the changes listed under Completed)
- `swift build` passes.
- `swift test --enable-code-coverage` passes: 45 Swift tests (12 `AgendumMacCoreTests` + 33 `AgendumMacWorkflowTests`).
- `/opt/homebrew/bin/python3 -m unittest discover -s Tests` passes: 48 tests (no Python changes).
- `/opt/homebrew/bin/python3 Scripts/python_coverage.py` passes: 464/505 lines (91.9%) for `Backend/agendum_backend/helper.py` (no backend changes).
- `git diff --check` passes.
- `swift run AgendumMac` launches without an immediate startup crash (smoke run held open ~5s before SIGTERM, exit code 143).

### App bundle smoke checkpoint (on `codex/app-bundle-smoke`, after the changes listed under Completed)
- `swift build` passes.
- `swift test --enable-code-coverage` passes: 47 Swift tests (14 `AgendumMacCoreTests` + 33 `AgendumMacWorkflowTests`).
- `/opt/homebrew/bin/python3 -m unittest discover -s Tests` passes: 48 tests (no Python changes).
- `/opt/homebrew/bin/python3 Scripts/python_coverage.py` passes: 464/505 lines (91.9%) for `Backend/agendum_backend/helper.py` (no backend changes).
- `git diff --check` passes.
- `Scripts/build_app_bundle.sh` succeeds; `.build/Agendum.app/Contents/MacOS/Agendum` exists and is executable; `plutil -lint .build/Agendum.app/Contents/Info.plist` passes; `plutil -extract` confirms `CFBundleIdentifier=com.danseely.agendum-mac`, `CFBundleExecutable=Agendum`, `CFBundleName=Agendum`, `LSMinimumSystemVersion=14.0`.

### Packaging matrix doc checkpoint (on `codex/packaging-matrix-doc`, after the changes listed under Completed)
This checkpoint is docs-only; no new gates were introduced and existing gates match the post-PR-#14 baseline.
- `swift build` passes.
- `swift test --enable-code-coverage` passes: 45 Swift tests (12 `AgendumMacCoreTests` + 33 `AgendumMacWorkflowTests`), unchanged from post-PR-#14 baseline.
- `/opt/homebrew/bin/python3 -m unittest discover -s Tests` passes: 48 tests (no Python changes).
- `/opt/homebrew/bin/python3 Scripts/python_coverage.py` passes: 464/505 lines (91.9%) for `Backend/agendum_backend/helper.py` (no backend changes).
- `git diff --check` passes.
- `swift run AgendumMac` launches without an immediate startup crash (smoke run held open ~5s before SIGTERM, exit code 143).

### Open task URL checkpoint (post-PR-#17)
- `swift build` passes.
- `swift test --enable-code-coverage` passes: 57 Swift tests (14 `AgendumMacCoreTests` + 43 `AgendumMacWorkflowTests`).
- `/opt/homebrew/bin/python3 -m unittest discover -s Tests` passes: 48 Python tests (no Python changes in this checkpoint).
- `/opt/homebrew/bin/python3 Scripts/python_coverage.py` passes at 91.9% for `Backend/agendum_backend/helper.py` (no backend changes in this checkpoint).
- `git diff --check` passes.
- `swift run AgendumMac` smoke held open ~5s before SIGTERM with no immediate startup crash. The build agent also recorded a manual click-through confirming a task URL opens in the default browser through the new `BackendStatusModel.openTaskURL(id:)` path.
- PR #17 included an in-scope drive-by fix to `BackendClientConfiguration.firstAncestor` resolving an infinite-loop bug introduced in PR #16; reviewer recommended KEEP rather than split the fix into a separate PR.

### Task list filtering checkpoint (post-PR-#18)
- `swift build` passes.
- `swift test --enable-code-coverage` passes: 70 Swift tests (14 `AgendumMacCoreTests` + 56 `AgendumMacWorkflowTests`).
- `/opt/homebrew/bin/python3 -m unittest discover -s Tests` passes: 48 Python tests (no Python changes in this checkpoint).
- `/opt/homebrew/bin/python3 Scripts/python_coverage.py` passes at 91.9% for `Backend/agendum_backend/helper.py` (no backend changes in this checkpoint).
- `git diff --check` passes.
- `swift run AgendumMac` smoke held open ~5s before SIGTERM with no immediate startup crash.

### Settings / auth-repair checkpoint (post-PR-#19)
- `swift build` passes.
- `swift test --enable-code-coverage` passes: 82 Swift tests.
- `/opt/homebrew/bin/python3 -m unittest discover -s Tests` passes: 61 Python tests.
- `/opt/homebrew/bin/python3 Scripts/python_coverage.py` passes at 92.4% (500/541 lines) for `Backend/agendum_backend/helper.py`.
- `git diff --check` passes.
- `swift run AgendumMac` smoke held open ~5s before SIGTERM with no immediate startup crash.
- In-scope drive-by: the `repairInstructions` string at `Backend/agendum_backend/helper.py:439` was unified behind the new `_format_repair_command` shared formatter so the new `auth.repairCommand` JSON field and the existing user-facing prose share one source of truth (and `shlex.quote` now safely handles space-bearing `GH_CONFIG_DIR` paths).

### Keyboard shortcuts + menu coverage checkpoint (post-PR-#20)
- `swift build` passes.
- `swift test --enable-code-coverage` passes: 103 Swift tests (+21 over the post-PR-#19 baseline of 82, all in `AgendumMacWorkflowTests` covering the new `TaskDashboardCommand` cases, the `availability(on:)` predicate, the `selectedTaskID` mirror, and the `newTask`-as-no-op contract).
- `/opt/homebrew/bin/python3 -m unittest discover -s Tests` passes: 61 Python tests.
- `/opt/homebrew/bin/python3 Scripts/python_coverage.py` passes at 92.4% for `Backend/agendum_backend/helper.py` (no Python changes in this checkpoint).
- `git diff --check` passes.
- `swift run AgendumMac` smoke held open ~5s before SIGTERM with no immediate startup crash; the build agent also recorded a manual menu click-through that confirmed each new shortcut fires the expected workflow path.

### Per-task error surfacing checkpoint (on `codex/per-task-error-surfacing`, after the changes listed under Completed)
- `swift build` passes.
- `swift test --enable-code-coverage` passes: 29 Swift tests (12 `AgendumMacCoreTests` + 17 `AgendumMacWorkflowTests`).
- `/opt/homebrew/bin/python3 -m unittest discover -s Tests` passes: 48 tests.
- `/opt/homebrew/bin/python3 Scripts/python_coverage.py` passes: 464/505 lines (91.9%) for `Backend/agendum_backend/helper.py` (no backend changes in this checkpoint).
- `git diff --check` passes.
- `swift run AgendumMac` launches without an immediate startup crash (smoke run held open ~5s before manual termination).
- Follow-up fix: `markReviewed`, `markDone`, and `remove` closures in `Sources/AgendumMac/AgendumMacApp.swift` now defer `selectedTask = nil` until after the action awaits and only clear when `backendStatus.errorForTask(id:)` is `nil`, so per-task errors stay visible inline in `TaskDetail` on failure. Validation: `swift build` passed; `swift test --enable-code-coverage` passed (29 Swift tests); `/opt/homebrew/bin/python3 -m unittest discover -s Tests` passed (48 tests); `git diff --check` passed.
- Manual SwiftUI smoke on `d163d02`: temporarily injected an `NSError` throw in `BackendStatusModel.removeTask`, ran `swift run AgendumMac`, clicked `Remove` on a selected task; confirmed selection stayed on the failing task, the red caption error rendered inline beneath the action buttons, and per-task scoping held when navigating between tasks. Smoke edit reverted via `git checkout --` after.
- Independent blind code review on `d163d02` (after the follow-up fix and smoke) returned no findings at the 75-confidence bar across correctness, standards, security, contract, and architecture lenses.

### History
- `swift build` passes.
- `swift test` passes: 8 Swift tests.
- `swift test --enable-code-coverage` passes; `BackendClient.swift` line coverage is 72.14% by `xcrun llvm-cov report`.
- `python3 -m unittest discover -s Tests` passes: 18 tests.
- `python3 Scripts/python_coverage.py` passes: 193/207 lines, 93.2% for `Backend/agendum_backend/helper.py`.
- Smoke-tested JSONL helper invocation with `workspace.current` and `auth.status`.
- `git diff --check` passes.
- PR #7 GitHub check `Test` passed for run `25229556371`.
- Local review validation before fixes: `git diff --check` passed, `/opt/homebrew/bin/python3 -m unittest discover -s Tests` passed, and `swift test --enable-code-coverage` passed.
- Local review-fix validation: `git diff --check` passed.
- Local review-fix validation: `/opt/homebrew/bin/python3 -m unittest discover -s Tests` passed: 32 tests.
- Local review-fix validation: `/opt/homebrew/bin/python3 Scripts/python_coverage.py` passed: 305/326 lines, 93.6% for `Backend/agendum_backend/helper.py`.
- Local review-fix validation: `swift test --enable-code-coverage` passed: 10 Swift tests.
- First fresh blind review validation: `gh pr checks 7` passed, `git diff --check feature/mac-prototype...codex/task-list-loading` passed, `/opt/homebrew/bin/python3 -m unittest discover -s Tests` passed, and `swift test --enable-code-coverage` passed.
- Second review-fix validation: `git diff --check` passed.
- Second review-fix validation: `/opt/homebrew/bin/python3 -m unittest discover -s Tests` passed: 32 tests.
- Second review-fix validation: `/opt/homebrew/bin/python3 Scripts/python_coverage.py` passed: 305/326 lines, 93.6% for `Backend/agendum_backend/helper.py`.
- Second review-fix validation: `swift test --enable-code-coverage` passed: 10 Swift tests.
- Blind review cycle 3 validation: `gh pr checks 7` passed, `git diff --check origin/feature/mac-prototype...origin/codex/task-list-loading` passed, `/opt/homebrew/bin/python3 -m unittest discover -s Tests` passed: 32 tests, `/opt/homebrew/bin/python3 Scripts/python_coverage.py` passed: 305/326 lines, 93.6%, and `swift test --enable-code-coverage` passed: 10 Swift tests.
- PR #7 final CI passed: GitHub Actions run `25230767259`.
- Early checkpoint validation: `/opt/homebrew/bin/python3 -m unittest discover -s Tests` passes: 39 tests.
- Early checkpoint validation: `swift test --enable-code-coverage` passes: 11 Swift tests.
- Early checkpoint validation: `git diff --check` passes.
- Final checkpoint validation: `/opt/homebrew/bin/python3 -m unittest discover -s Tests` passes: 39 tests.
- Final checkpoint validation: `/opt/homebrew/bin/python3 Scripts/python_coverage.py` passes: 396/419 lines, 94.5% for `Backend/agendum_backend/helper.py`.
- Final checkpoint validation: `swift build` passes.
- Final checkpoint validation: `swift test --enable-code-coverage` passes: 11 Swift tests.
- Final checkpoint validation: `git diff --check` passes.
- PR #9 GitHub Actions `Test` check is passing on the current head.
- PR #9 review-fix validation: `/opt/homebrew/bin/python3 -m unittest discover -s Tests` passes: 40 tests.
- PR #9 review-fix validation: `/opt/homebrew/bin/python3 Scripts/python_coverage.py` passes: 405/428 lines, 94.6% for `Backend/agendum_backend/helper.py`.
- PR #9 review-fix validation: `swift build` passes.
- PR #9 review-fix validation: `swift test --enable-code-coverage` passes: 11 Swift tests.
- PR #9 review-fix validation: `git diff --check` passes.
- PR #9 review-fix GitHub Actions `Test` check passed after the fix push.
- Launch smoke: `swift run AgendumMac` built successfully and the app stayed running until manually interrupted after a brief launch window; no immediate startup crash was observed.
- PR #9 blind-review fix validation: `/opt/homebrew/bin/python3 -m unittest discover -s Tests` passes: 42 tests.
- PR #9 blind-review fix validation: `/opt/homebrew/bin/python3 Scripts/python_coverage.py` passes: 416/455 lines, 91.4% for `Backend/agendum_backend/helper.py`.
- PR #9 blind-review fix validation: `swift build` passes.
- PR #9 blind-review fix validation: `swift test --enable-code-coverage` passes: 11 Swift tests.
- PR #9 blind-review fix validation: `git diff --check` passes.
- PR #9 blind-review fix GitHub Actions `Test` check passed after the fix push.
- PR #9 second blind-review fix validation: `/opt/homebrew/bin/python3 -m unittest discover -s Tests` passes: 43 tests.
- PR #9 second blind-review fix validation: `/opt/homebrew/bin/python3 Scripts/python_coverage.py` passes: 416/455 lines, 91.4% for `Backend/agendum_backend/helper.py`.
- PR #9 second blind-review fix validation: `swift test --enable-code-coverage` passes: 11 Swift tests.
- PR #9 second blind-review fix validation: `git diff --check` passes.
- PR #9 second blind-review fix GitHub Actions `Test` check passed after the fix push.
- PR #9 third blind review checked passing GitHub Actions, clean `git diff --check origin/feature/mac-prototype...origin/codex/task-detail-actions-sync`, and targeted sync helper tests.
- SwiftUI workflow coverage plan recorded in `docs/testing.md`; no implementation validation has run for that future checkpoint yet.
- SwiftUI workflow checkpoint validation: `swift test --enable-code-coverage` passes with 22 Swift tests, including 11 `AgendumMacWorkflowTests`.
- SwiftUI workflow checkpoint validation: `swift build` passes.
- SwiftUI workflow checkpoint validation: `/opt/homebrew/bin/python3 -m unittest discover -s Tests` passes: 43 tests.
- SwiftUI workflow checkpoint validation: `/opt/homebrew/bin/python3 Scripts/python_coverage.py` passes: 416/455 lines, 91.4% for `Backend/agendum_backend/helper.py`.
- SwiftUI workflow checkpoint validation: `git diff --check` passes.
- PR #9 final pre-merge GitHub Actions `Test` check passed before merge.
- `.github/workflows/test.yml` parses as YAML with Ruby's stdlib parser.
- GitHub Actions PR run `25076611284` passed for PR #3 before the checkout v5 update.
- GitHub Actions PR run `25076677868` passed for PR #3 after the checkout v5 update.
- GitHub Actions PR run `25076838730` passed for PR #3 after removing duplicate branch push triggers.
- GitHub Actions PR run `25077164616` passed for PR #3 after enabling all pull-request targets.
- GitHub Actions checks for parent PR #2 are passing after PR #3 merged into `feature/mac-prototype`.
- CI push triggers now exclude `feature/mac-prototype`; the parent PR handles validation for that branch.
- GitHub Actions PR run `25077788303` passed for PR #4.
- GitHub Actions PR run `25192465596` passed for PR #5.
- GitHub Actions PR run `25193185925` passed for PR #5 after timeout/lifecycle fixes and SwiftPM coverage CI.
- GitHub Actions PR run `25194092308` passed for PR #5 after the final planning-doc update before merge.
- `git pull --ff-only` on `feature/mac-prototype` reported already up to date after merge.
- `python3 -m unittest discover -s Tests` passes: 25 tests.
- `python3 Scripts/python_coverage.py` passes: 252/267 lines, 94.4% for `Backend/agendum_backend/helper.py`.
- `swift build` passes.
- `swift test --enable-code-coverage` passes: 9 Swift tests.
- `git diff --check` passes.
- GitHub Actions PR run `25194659243` passed for PR #6.
- GitHub Actions PR run `25194851503` passed for PR #6 after the blank-namespace review fix.
- `/opt/homebrew/bin/python3 -m unittest discover -s Tests` passes: 32 tests.
- `/opt/homebrew/bin/python3 Scripts/python_coverage.py` passes: 305/326 lines, 93.6% for `Backend/agendum_backend/helper.py`.
- `swift build` passes.
- `swift test --enable-code-coverage` passes: 10 Swift tests.
- `git diff --check` passes.
- `python3 -m unittest discover -s Tests` fails in the current shell because `python3` resolves to pyenv Python 3.10.2, which lacks `tomllib`; use `/opt/homebrew/bin/python3` for local helper validation.
- Launch smoke completed with `swift run AgendumMac`; deeper UI workflow testing remains manual.
- PR #10 review-fix validation: `swift build` passes, `swift test --enable-code-coverage` passes with 22 Swift tests, `/opt/homebrew/bin/python3 -m unittest discover -s Tests` passes with 43 tests, `/opt/homebrew/bin/python3 Scripts/python_coverage.py` reports 416/455 lines (91.4%) for `Backend/agendum_backend/helper.py`, and `git diff --check` passes.
- PR #10 review-fix sanity check: temporarily removed the `tasks = []` clear in `Sources/AgendumMacWorkflow/TaskWorkflowModel.swift` `refresh()` catch and reran `swift test --filter TaskWorkflowModelTests/testRefreshFailureClearsTasksAndSurfacesError`; the test failed as expected, then passed again after restoring the line.

### Notifications + dock badge checkpoint (post-PR-#21)
- `swift build` passes.
- `swift test --enable-code-coverage` passes with 119 Swift tests (+16 over the post-PR-#20 baseline of 103).
- `/opt/homebrew/bin/python3 -m unittest discover -s Tests` passes with 61 Python tests.
- `/opt/homebrew/bin/python3 Scripts/python_coverage.py` passes at 92.4% (no helper changes in item 5).
- `git diff --check` passes.
- `swift run AgendumMac` smoke held open ~5s before SIGTERM; no immediate startup crash.
- CI ran `Test` after the `@preconcurrency UserNotifications` fix (commit `5f54489`) on PR #21 and passed before merge.

### @Observable migration checkpoint (on `codex/a1-observable-migration`)
- Scope: A1 / issue #27 — `BackendStatusModel` migrated to `@Observable`; `AgendumMacApp.swift` updated to `@State` / `@Environment(BackendStatusModel.self)` / plain stored properties; `import Combine` removed from `TaskWorkflowModel.swift`; `import Observation` added.
- `swift build`: passes. (`Build complete! (4.01s)`)
- `swift test --enable-code-coverage`: passes — `Executed 119 tests, with 0 failures (0 unexpected) in 1.520 (1.526) seconds`. No test depended on `objectWillChange`; suite count unchanged from the post-PR-#21 baseline.
- `/opt/homebrew/bin/python3 -m unittest discover -s Tests`: passes — `Ran 61 tests in 2.883s OK`. No Python touched.
- `swift run AgendumMac`: built clean and held open >5s without crash; SIGTERM exited cleanly. Helper subprocess discovery from sibling `../agendum` is unchanged (pre-existing behavior; not in scope for A1).
- `git diff --check`: passes.

### os.Logger checkpoint (on `codex/a2-os-logger`)
- Scope: A2 / issue #29 — added `Sources/{AgendumMacCore,AgendumMacWorkflow,AgendumMac}/Logging.swift` declaring a per-target `let logger = Logger(subsystem: "com.danseely.agendum-mac", category: <backend|workflow|ui>)`. Replaced silent `try?` swallows in `BackendClient.close()` and `BackendStatusModel.defaultNotifier` with `logger.error("...: \(error.localizedDescription, privacy: .public)")`. The deinit-path `try? input.close()` was kept intentionally with a comment (no logger context available there). Added `logger.notice` lifecycle logs at: backend client spawn / restart / close / timeout / helper-terminated; `BackendStatusModel.refresh` start/ok/error; `selectWorkspace` start/ok/error; `forceSync` start/state/error/timeout/auth-token-invalidation; per-task actions (`markSeen`/`markReviewed`/`markInProgress`/`moveToBacklog`/`markDone`/`removeTask`) start/error via `performTaskAction(name:taskID:)`; `openTaskURL` start/no-URL/open-failed; `createManualTask` start/ok/error; `refreshDiagnostics` error; UI notification authorization request outcome; dock badge writes. No `print(` remains in `Sources/`.
- `swift build`: passes. (`Build complete! (3.94s)`)
- `swift test --enable-code-coverage`: passes — `Executed 119 tests, with 0 failures (0 unexpected) in 1.133 (1.139) seconds`. Suite count unchanged from the post-A1 baseline of 119; no test depended on `print` output.
- `/opt/homebrew/bin/python3 -m unittest discover -s Tests`: passes — `Ran 61 tests in 2.911s OK`. No Python touched.
- `swift run AgendumMac` + `log show --predicate 'subsystem == "com.danseely.agendum-mac"' --last 1m --info`: app launched cleanly; representative lines captured during the smoke run:
  - `2026-05-03 21:57:27.053766-0400 AgendumMac: [com.danseely.agendum-mac:workflow] BackendStatusModel.refresh start`
  - `2026-05-03 21:57:27.054034-0400 AgendumMac: [com.danseely.agendum-mac:backend] Spawning backend helper process at /Users/dseely/dev/agendum-mac/Backend/agendum_backend_helper.py.`
  - `2026-05-03 21:57:28.039816-0400 AgendumMac: [com.danseely.agendum-mac:workflow] BackendStatusModel.refresh ok: 15 tasks`
- `git diff --check`: passes.
- `git grep -nP '^\s*print\(' -- Sources/`: no matches.

### Fork-and-vendor checkpoint (on `codex/b1-fork-and-vendor`)
- Scope: B1 / issue #31 — flat-copied `../agendum/src/agendum/` to `Backend/agendum_engine/agendum/`; added `Backend/agendum_engine/LICENSE` (Apache-2.0, verbatim from upstream) and `Backend/agendum_engine/README.md` recording the fork-point commit `b62a45c6a28f8ffd4b57a597de4744dc83d0d94d` and divergence policy. `_bootstrap_agendum_import()` in `Backend/agendum_backend/helper.py` now prepends `Backend/agendum_engine/` to `sys.path` unconditionally (no sibling fallback). `Tests/test_backend_helper_process.py` uses the in-tree path. `.github/workflows/test.yml` no longer checks out `danseely/agendum`. Engine import name (`agendum`) preserved, so other call sites are untouched.
- `swift build`: passes. (`Build complete! (2.74s)`)
- `swift test --enable-code-coverage`: passes — `Executed 119 tests, with 0 failures (0 unexpected) in 1.073 (1.080) seconds`. Suite count unchanged from the post-A2 baseline.
- `/opt/homebrew/bin/python3 -m unittest discover -s Tests`: passes — `Ran 61 tests in 2.994s OK`.
- `/opt/homebrew/bin/python3 Scripts/python_coverage.py`: passes — `Backend/agendum_backend/helper.py: 499/540 lines (92.4%)` (≥91% gate).
- Sibling-isolation gate: with `/Users/dseely/dev/agendum` renamed to `/Users/dseely/dev/agendum.bak`, re-ran `swift test --enable-code-coverage` (119/0/0 in 1.027s), `python3 -m unittest discover -s Tests` (61/0 in 2.794s), `python3 Scripts/python_coverage.py` (499/540 = 92.4%), and `swift run AgendumMac` (built clean, ran >5s, terminated cleanly). Sibling restored afterward.
- `git diff --check`: passes (on the three modified files; the new `Backend/agendum_engine/` tree is untracked-then-staged and reproduces the upstream `src/agendum/` byte-for-byte).

## Changed files
- `Scripts/build_app_bundle.sh` (new, executable): assembles `.build/Agendum.app` from the SwiftPM `AgendumMac` release product, derives `CFBundleShortVersionString` from `git describe` (fallback `0.1.0+dev`) and `CFBundleVersion` from `git rev-list HEAD --count` (fallback `1`), substitutes both into the plist template, and lints the result with `plutil -lint`.
- `Sources/AgendumMac/Info.plist.template` (new): source of truth for the bundle plist; defines `CFBundleIdentifier=com.danseely.agendum-mac`, `CFBundleName=Agendum`, `CFBundleExecutable=Agendum`, `CFBundlePackageType=APPL`, `LSMinimumSystemVersion=14.0`, `NSHighResolutionCapable=true`, with `__SHORT_VERSION__` / `__BUNDLE_VERSION__` placeholders.
- `Package.swift`: added `exclude: ["Info.plist.template"]` to the `AgendumMac` executable target so SwiftPM does not treat the plist template as a resource.
- `Tests/AgendumMacCoreTests/BackendClientTests.swift`: two new tests pin the existing `BackendClientConfiguration.discoverDevelopmentRepositoryRoot(...)` walker against the `.build/Agendum.app/Contents/MacOS/` layout (positive resolves to repo root via the `Backend/agendum_backend_helper.py` marker; negative falls back to the supplied `currentDirectoryURL` when no marker is found).
- `.github/workflows/test.yml`: appended a `Build app bundle smoke` step after the existing Swift coverage step, running `Scripts/build_app_bundle.sh` and asserting the bundle layout + `plutil -lint` succeed.
- `README.md`: appended one paragraph documenting the developer-convenience `.app` build.
- `docs/decisions.md`: appended the 2026-05-02 Slice A bundle-smoke decision (bundle identity, version policy, helper-discovery contract; still-deferred items).
- `docs/packaging.md`: annotated deferred decisions 8/9/10 with `(answered 2026-05-02: see decisions.md)`.
- `docs/plan.md`: rewrote the "Current Implementation Checkpoint" paragraph for the bundle-smoke checkpoint.
- `docs/status.md`: bumped `Last updated`, replaced the Current milestone, moved PR #15 to Done, replaced In progress with the bundle-smoke bullet, refreshed Next.
- `docs/handoff.md`: refreshed Current objective / Branch / Repo state / Next actions / After checkpoint, added the cleanup line for `codex/packaging-matrix-doc`, and appended the App bundle smoke checkpoint validation block.

## Previous checkpoint changed files (PR #15, packaging matrix doc)
- `docs/packaging.md` (new): packaging matrix with distribution-channel and Python helper runtime sections, interactions with prior decisions, prototype-phase recommendation, and 10 deferred decisions.
- `docs/decisions.md`: appended a 2026-05-02 entry naming `docs/packaging.md` as canonical packaging matrix and recording the prototype-phase posture (continue developer-only `swift run AgendumMac`; defer channel and Python-runtime choices to user input).

## Previous checkpoint changed files (PR #14, structured error mapping)
- `Sources/AgendumMacWorkflow/TaskWorkflowModel.swift`: extended `PresentedError.from(_:)` to map every `BackendClientError` case to a stable `client.*` code plus a human-readable recovery hint; non-`BackendClientError` types fall back to `client.unknown`.
- `Tests/AgendumMacWorkflowTests/TaskWorkflowModelTests.swift`: added per-case mapping tests and a `client.unknown` fallback test.

## Previous checkpoint changed files (PR #13, sync lifecycle and structured error presentation)
- `Sources/AgendumMacWorkflow/TaskWorkflowModel.swift`: added `PresentedError`, `lastSyncLabel`, `hasAttentionItems`, clock seam, structured per-task errors.
- `Sources/AgendumMac/AgendumMacApp.swift`: two-line message+recovery captions globally and per-task; `Last synced` and `Needs attention` indicators in the sync row.
- `Sources/AgendumMacCore/BackendClient.swift`: public initializer on `BackendErrorPayload` so workflow tests can construct payloads from outside `AgendumMacCore`.
- `Tests/AgendumMacWorkflowTests/TaskWorkflowModelTests.swift`: 7 new tests covering `PresentedError.from(_:)` helper-payload extraction, generic-error fallback, refresh/task-action structured recovery, last-sync label formatting, and `hasAttentionItems`.

## Previous checkpoint changed files (PR #11, manual task creation UX)
- `Backend/agendum_backend/helper.py`: added `task.createManual` dispatch, `create_manual_task` function, and payload helpers (`_required_string`, `_optional_create_string`, `_optional_tag_list`); imports `create_manual_task` from `agendum.task_api`.
- `Tests/test_backend_helper.py`: four new tests for manual task creation (full payload, minimal payload, namespaced DB, invalid-payload table).
- `Tests/test_backend_helper_process.py`: `test_task_create_manual_persists_through_jsonl_process` covering create, list, and invalid-payload behavior over one helper process.
- `Sources/AgendumMacCore/BackendClient.swift`: `createManualTask(title:project:tags:)` plus `TaskCreateManualRequestPayload`.
- `Tests/AgendumMacCoreTests/BackendClientTests.swift`: `testClientCreatesManualTask` for request/response coverage.
- `Sources/AgendumMacWorkflow/TaskWorkflowModel.swift`: `AgendumBackendServicing.createManualTask` and `BackendStatusModel.createManualTask` returning `Bool`.
- `Tests/AgendumMacWorkflowTests/TaskWorkflowModelTests.swift`: success and failure tests for `createManualTask`, plus matching `FakeBackend` stub method.
- `Sources/AgendumMac/AgendumMacApp.swift`: "New Task" toolbar button, sheet presentation state, and `CreateManualTaskSheet` form.
- PR #10 changed `Package.swift`, `Sources/AgendumMac/AgendumMacApp.swift`, `Sources/AgendumMacWorkflow/TaskWorkflowModel.swift`, `Tests/AgendumMacWorkflowTests/TaskWorkflowModelTests.swift`, and `docs/decisions.md`, `docs/status.md`, `docs/handoff.md`, `docs/plan.md`.
- PR #9 changed `Backend/agendum_backend/helper.py`.
- PR #9 changed `Sources/AgendumMacCore/BackendClient.swift`.
- PR #9 changed `Sources/AgendumMac/AgendumMacApp.swift`.
- PR #9 changed `Tests/AgendumMacCoreTests/BackendClientTests.swift`.
- PR #9 changed `Tests/test_backend_helper.py`.
- PR #9 changed `Tests/test_backend_helper_process.py`.
- PR #9 changed `docs/testing.md`, `docs/plan.md`, `docs/status.md`, and `docs/handoff.md`.

## Risks / blockers
- A Mac App Store build is likely harder if the app depends on launching external `gh` and sharing `gh` auth files.
- The current agendum MCP/task API is read/create-heavy and does not yet expose all actions the GUI needs.
- Packaging Python plus dependencies inside a signed app needs explicit design.
- Finder-launched apps do not inherit shell `PATH`, so `gh` discovery cannot assume the terminal environment.
- SwiftPM development runs now prefer common Homebrew Python paths, but the production helper runner and bundled Python strategy are still unresolved.
- Current `gh auth login` flow is terminal-oriented and needs Mac-specific repair UX.
- SQLite ownership must stay behind the helper unless a later decision permits direct Swift DB access.

## Next actions
Conditional on the probe results above:

- **If PR #23 is open**: review and merge it (or push fixes if review surfaces something). Run `gh pr checks 23` first — if CI red, push fix; if green and unreviewed, run a review pass.
- **If PR #23 is merged and no Phase 1 leaf is in flight**: file the next leaf to start (default A1, highest leverage), citing parent epic #24. Draft body lives in `docs/research/proposed-issues.md`. Per the user's global GitHub rule, every issue filing requires explicit user approval. Once filed, cut `codex/<slug>` from `feature/mac-prototype`, implement, open the leaf PR. Phase 1 leaves (A1 `@Observable` / A2 `os.Logger` / B1 fork-and-vendor) are parallel-safe.
- **If a leaf-work PR is open**: drive that one to merge before starting another. `gh pr view <N>` for current state; push fixes if needed; run reviewer pass once green.
- **If a leaf-work PR is merged**: roll forward `docs/handoff.md`, `docs/status.md`, `docs/decisions.md` as appropriate, then move to the next leaf in the phase plan (`docs/research/synthesis.md`).

## After checkpoint
The active checkpoint at any moment is whichever leaf-work PR is open, or the next-leaf-to-file if none is in flight. The arc finishes when issues #24, #25, #26 are all closed.

## Drift from original plan
- Approved deviation: GUI work moved from `../agendum` into this standalone project.
- Approved deviation: public `main` is README-only; prototype work lives on stacked feature branches.
- Resolved stack state: `codex/task-list-loading` was temporarily based on PR #6, then rebased onto `feature/mac-prototype` after PR #6 merged.
- No new unapproved drift found during the PR #9 planning-doc update.
- No new unapproved drift found during the PR #9 focused review fixes.
- Blind-review sync-force finding confirmed implementation drift from `docs/backend-contract.md`; fixed by bringing `sync.force` behavior back in line with the contract.
- Second blind-review finding confirmed test/documentation drift around subprocess coverage; fixed by adding the missing subprocess JSONL sync test.
- Third blind review found no new drift.
- SwiftUI workflow coverage residual risk has been reduced by the new fake-backed workflow target and tests.
- No new unapproved drift found during the SwiftUI workflow extraction; the new `AgendumMacWorkflow` target is recorded in `docs/decisions.md`.
- PR #10 review surfaced one test-intent gap (now fixed) and one decisions-log scope omission (now expanded), so the planning-handoff drift check approach continues to be useful.
- No new unapproved drift after PR #10 merge; manual task creation UX is the next live-slice gap and was already named in earlier handoff `After checkpoint` notes.
- Manual task creation checkpoint stays in scope of the named next-action plan; no unapproved drift introduced by the helper command, Swift client, workflow plumbing, or SwiftUI sheet.
- Per-task error surfacing checkpoint stays in scope of the post-PR-#11 next-action plan; no unapproved drift introduced by the new `taskActionErrors` map, the task-scoped `performTaskAction`, the SwiftUI detail-pane error caption, or the new fake-backed workflow tests.
- Item 1 (PR #17) included an in-scope drive-by fix to `BackendClientConfiguration.firstAncestor` that resolved an infinite-loop bug introduced in PR #16; the reviewer recommended KEEP rather than split it into a separate PR, so the fix landed inside the item-1 PR rather than as its own checkpoint.
- 2026-05-03 plan revision: large-but-approved deviation. The user explicitly directed "rip all Python out" after the three architecture-direction research streams completed. This contradicts and supersedes three prior `docs/plan.md` non-goals ("No decision has been made to rewrite the Python backend in Swift"; "Whether Swift ever reads SQLite directly. Current bias: no"; "Out Of Scope Until Later: full Swift rewrite of the sync engine"). All three are reversed; the new direction is recorded in `docs/decisions.md` under "2026-05-03 — Plan revision: standalone Swift app" and the new milestone arc is in `docs/plan.md`.
- Five-item orchestration shipped without scope drift outside the explicitly-recorded drive-bys (item 1 `firstAncestor` infinite-loop fix; item 3 helper.py:439 `repairInstructions` shared-formatter unification). Both were called out in their PR bodies and reviewer-approved as KEEP.
