# Handoff

## Current objective
Add `docs/packaging.md` enumerating Mac distribution channels and Python helper runtime options on `codex/packaging-matrix-doc` → `feature/mac-prototype`. Live PR/CI/review state lives in `gh pr view <N>`.

## Branch
`codex/packaging-matrix-doc`, branched from updated `feature/mac-prototype` after PR #14 merged.

## Repo state
- HEAD: `codex/packaging-matrix-doc`; local branch starts from the post-PR-#14 tip of `feature/mac-prototype`. Working tree was clean before edits (apart from untracked `.claude/`).
- Integration branch: `feature/mac-prototype`; PR #14 (structured error mapping) merged on 2026-05-02 (squash merge `e05efa7`).
- Previous checkpoint PR: `https://github.com/danseely/agendum-mac/pull/14`, merged into `feature/mac-prototype` on 2026-05-02 (squash merge `e05efa7`).
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
- Local cleanup: deleted local `codex/test-coverage-reporting`, `feature/backend-helper`, and `codex/document-branch-discipline` branches after merge. The `codex/manual-task-creation` local branch was removed by the PR #11 merge flow; remote PR branches `origin/codex/manual-task-creation` and `origin/codex/swiftui-workflow-coverage` were deleted on the remote. Deleted local `codex/per-task-error-surfacing` after PR #12 merge. Deleted local `codex/structured-error-mapping` after PR #14 merge.
- Branch discipline: do not push directly to `feature/mac-prototype`; use short-lived branches and PRs targeting `feature/mac-prototype` unless explicitly requested otherwise.
- Sibling repo requirement: the backend helper imports from `../agendum/src`, so `danseely/agendum` must be checked out as a sibling directory for local Python tests, helper subprocess runs, and `swift run AgendumMac` to work. CI replicates this with a sibling checkout in `.github/workflows/test.yml`.
- Last validation date: 2026-05-02

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

### Packaging matrix doc checkpoint (on `codex/packaging-matrix-doc`, after the changes listed under Completed)
This checkpoint is docs-only; no new gates were introduced and existing gates match the post-PR-#14 baseline.
- `swift build` passes.
- `swift test --enable-code-coverage` passes: 45 Swift tests (12 `AgendumMacCoreTests` + 33 `AgendumMacWorkflowTests`), unchanged from post-PR-#14 baseline.
- `/opt/homebrew/bin/python3 -m unittest discover -s Tests` passes: 48 tests (no Python changes).
- `/opt/homebrew/bin/python3 Scripts/python_coverage.py` passes: 464/505 lines (91.9%) for `Backend/agendum_backend/helper.py` (no backend changes).
- `git diff --check` passes.
- `swift run AgendumMac` launches without an immediate startup crash (smoke run held open ~5s before SIGTERM, exit code 143).

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

## Changed files
- `docs/packaging.md` (new): packaging matrix with distribution-channel and Python helper runtime sections, interactions with prior decisions, prototype-phase recommendation, and 10 deferred decisions.
- `docs/decisions.md`: appended a 2026-05-02 entry naming `docs/packaging.md` as canonical packaging matrix and recording the prototype-phase posture (continue developer-only `swift run AgendumMac`; defer channel and Python-runtime choices to user input).
- `docs/plan.md`: rewrote the "Current Implementation Checkpoint" paragraph and the follow-up paragraph for the packaging-matrix doc checkpoint.
- `docs/status.md`: bumped `Last updated`, replaced the Current milestone, moved PR #14 into Done with squash-merge `e05efa7`, recorded the new branch creation, replaced In progress with the packaging-doc bullet, and refreshed Next.
- `docs/handoff.md`: refreshed Current objective / Branch / Repo state / Next actions / After checkpoint, added the cleanup line for `codex/structured-error-mapping`, and appended the Packaging matrix doc checkpoint validation block.

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
1. Run `gh pr view <N>` and `gh pr checks <N>` for the packaging-matrix-doc PR once opened, then branch on the result:
   - CI failing: investigate and push fixes to `codex/packaging-matrix-doc`.
   - CI green, no review yet: run a blind review pass; address findings as new commits.
   - Review clean, PR still draft: mark ready.
   - Merged: fast-forward local `feature/mac-prototype`, then pick the next checkpoint.

## After checkpoint
- Once distribution channel and Python helper runtime are picked, scope the first code-bearing packaging slice (likely Slice A: bundle-from-SwiftPM smoke under `Scripts/build_app_bundle.sh`).

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
