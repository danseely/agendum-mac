# Status

Last updated: 2026-05-03 (A1 @Observable migration in flight)

## Current milestone
"Standalone Swift app" arc. The five-item live-slice orchestration finished 2026-05-03 (PRs #17–#21 squash-merged into `feature/mac-prototype`); after that, three research streams (`docs/research/{backend-engine,data-store,architecture}.md`) produced a cross-stream synthesis (`docs/research/synthesis.md`) and drafted GitHub issue text (`docs/research/proposed-issues.md`). The plan revision is recorded in `docs/decisions.md` under "2026-05-03 — Plan revision: standalone Swift app." The next implementation step is filing the three epic tracking issues (A / B / C) plus the Phase 1 work issues (A1 `@Observable` migration, A2 `os.Logger`, B1 fork-and-vendor) and merging the planning-doc PR that captures all of this.

## Milestone exit criteria
- `docs/backend-contract.md` exists and covers task loading, task actions, sync, namespace, auth, error schema, and protocol versioning. Done.
- Bridge choice is recorded in `docs/decisions.md`. Done.
- Next implementation step is precise enough for a fresh session to start without re-planning. Done.
- `docs/testing.md` records the testing strategy and milestone gates. Done.
- First follow-up test batch is planned before Swift helper wiring or new backend surface. Done.
- Helper subprocess JSONL tests cover the existing process boundary. Done.
- Missing helper protocol edge-case tests cover existing commands. Done.
- Backend coverage reporting command exists and has a recorded baseline. Done.
- GitHub Actions workflow runs the current local test pipeline. Done.

## Done
- Created a new local project outside `../agendum`.
- Added a SwiftUI-first macOS app scaffold with sample task data.
- Moved planning and evaluation docs into this repo.
- Initialized local Git repository.
- Verified the scaffold with `swift build`.
- Sent the plan through independent agent review and incorporated the review into planning docs.
- Re-vetted and accepted `docs/backend-contract.md` as clean for first implementation pass.
- Published README-only `main` to `https://github.com/danseely/agendum-mac`.
- Created `feature/mac-prototype` as the broad prototype integration branch.
- Pushed `feature/mac-prototype`.
- Opened draft parent PR #2: `https://github.com/danseely/agendum-mac/pull/2`.
- Retargeted backend-helper PR #1 to `feature/mac-prototype`: `https://github.com/danseely/agendum-mac/pull/1`.
- Added `Backend/agendum_backend/helper.py` with the v0 JSONL request/response envelope.
- Implemented `workspace.current` and `auth.status` in the helper.
- Added focused helper tests in `Tests/test_backend_helper.py`.
- Pushed `feature/backend-helper`.
- Fixed PR review finding: non-object JSON requests now return a `payload.invalid` envelope instead of crashing.
- PR #1 was merged into `feature/mac-prototype`.
- Added `docs/testing.md` and linked testing gates into the plan.
- Added helper subprocess integration tests in `Tests/test_backend_helper_process.py`.
- Expanded helper unit tests in `Tests/test_backend_helper.py`.
- Added `Scripts/python_coverage.py` for backend helper coverage reporting.
- Recorded initial backend helper coverage: 193/207 lines, 93.2%.
- Clarified that the Python coverage script is temporary/helper-only; Swift app coverage should use SwiftPM coverage now and Xcode/`xccov` once an Xcode app project exists.
- Added `.github/workflows/test.yml` to run backend coverage, Python tests, Swift build, and whitespace checks in CI.
- PR #3 merged the testing baseline and CI workflow into `feature/mac-prototype`.
- Cleaned up local topic branches after the merge.
- PR #4 recorded branch discipline: future changes should land on `feature/mac-prototype` only through PRs, not direct pushes.
- Added `AgendumMacCore`, a testable Swift target for backend-helper request/response models and long-lived JSONL process wiring.
- Wired the SwiftUI sidebar to load `workspace.current` and `auth.status` from the helper and show workspace/auth state.
- Added Swift tests that exercise multiple requests against one real helper process and verify backend error mapping.
- Updated CI to run `swift test --enable-code-coverage` in addition to `swift build`.
- Opened draft PR #5: `https://github.com/danseely/agendum-mac/pull/5`.
- Sent PR #5 through a separate review pass; addressed helper timeout/lifecycle risk and expanded Swift helper-client coverage.
- PR #5 latest CI run passed after review fixes: `25193185925`.
- PR #5 was marked ready and merged into `feature/mac-prototype`: `https://github.com/danseely/agendum-mac/pull/5`.
- Pulled `feature/mac-prototype` after merge and created `codex/workspace-selection` for the next checkpoint.
- Implemented `workspace.list` in the helper with base workspace plus discovered namespace directories.
- Implemented `workspace.select` in the helper with namespace validation, config creation, in-memory helper state update, auth status refresh, and idle sync status stub.
- Added backend unit and subprocess tests for workspace listing, selection, invalid namespace handling, and shared helper-process state.
- Added Swift client models/methods for workspace listing and selection.
- Added Swift client coverage for selecting/listing workspaces through one helper process, including explicit `namespace: null` base selection.
- Wired the sidebar status area to load workspace options and switch workspaces through a menu.
- Opened draft PR #6: `https://github.com/danseely/agendum-mac/pull/6`.
- Addressed PR #6 review finding: blank string namespaces are rejected; base selection requires `namespace: null`.
- PR #6 latest CI run passed after the review fix: `25194851503`.
- PR #6 was marked ready for review.
- PR #6 was merged into `feature/mac-prototype` on 2026-05-01.
- Fast-forwarded local `feature/mac-prototype` to PR #6 squash merge `f53c62e`.
- Rebasing `codex/task-list-loading` onto `feature/mac-prototype` completed after PR #6 merged.
- Created `codex/task-list-loading` from `codex/workspace-selection` for the next stacked checkpoint.
- Implemented `task.list` in `Backend/agendum_backend/helper.py` using the selected workspace DB and the existing `agendum.task_api.list_tasks`.
- Added task-list payload validation and lower-camel-case task bridge payload mapping.
- Added backend unit and subprocess coverage for `task.list`, selected-workspace DB loading, filters, and invalid payloads.
- Added `AgendumTask` and `listTasks(...)` to `Sources/AgendumMacCore/BackendClient.swift`.
- Replaced hard-coded SwiftUI sample tasks with backend-loaded tasks in `Sources/AgendumMac/AgendumMacApp.swift`.
- Added Swift client coverage for `task.list` request encoding and task decoding.
- Committed and pushed `codex/task-list-loading` as `feeee62`.
- Opened draft PR #7: `https://github.com/danseely/agendum-mac/pull/7`.
- Reviewed PR #7 locally and fixed/pushed the first findings in commit `fbe2e57`: stale task state on reload failure, invalid `task.list` payloads touching storage before validation, and stale handoff HEAD metadata.
- Ran a fresh blind review of PR #7 and fixed/pushed the next findings in commit `ce6f48c`: selected task ID carryover across workspace reloads and stale planning-doc state.
- Ran blind review cycle 1 after `ce6f48c`; it found no code-level bugs/regressions and only stale planning-doc state.
- Ran blind review cycle 2 after `810f56f`; it found no code-level bugs/regressions and only next-action drift in planning docs.
- Ran blind review cycle 3 after `4df64c6`; it found no actionable bugs, regressions, missing required tests, or stale project-memory docs.
- PR #7 was marked ready and merged into `feature/mac-prototype` on 2026-05-01 with squash merge `8e71589`.
- Local `feature/mac-prototype` was fast-forwarded to `8e71589`.
- PR #8 merged the post-PR #7 planning docs into `feature/mac-prototype` with squash merge `42f06aa`.
- Created `codex/task-detail-actions-sync` from updated `feature/mac-prototype`.
- Implemented helper commands for `task.get`, `task.markReviewed`, `task.markInProgress`, `task.moveToBacklog`, `task.markDone`, `task.markSeen`, `task.remove`, `sync.status`, and `sync.force`.
- Added backend unit and subprocess coverage for task detail/action commands and sync status/force behavior.
- Added Swift client methods and coverage for task detail/actions and sync commands.
- Wired the SwiftUI dashboard to show sync status, run force sync, and perform source-aware task actions from the detail pane.
- Opened draft PR #9: `https://github.com/danseely/agendum-mac/pull/9`.
- PR #9 is open as a draft, has a clean merge state, and its GitHub Actions `Test` check is passing on the current head.
- Focused PR #9 review found and fixed two issues: unexpected sync exceptions now produce an error sync status instead of leaving helper state `running`, and SwiftUI manual status actions are limited to backend `manual` tasks instead of all items in the Issues & Manual section.
- Local review-fix validation passed: `/opt/homebrew/bin/python3 -m unittest discover -s Tests` ran 40 tests, `/opt/homebrew/bin/python3 Scripts/python_coverage.py` reported 405/428 lines (94.6%), `swift build` passed, `swift test --enable-code-coverage` ran 11 tests, and `git diff --check` passed.
- PR #9 review fixes were pushed and GitHub Actions `Test` passed on the updated branch.
- `swift run AgendumMac` built the app and stayed running until manually interrupted after a brief launch smoke test; no immediate startup crash was observed.
- Fresh blind review of PR #9 found two sync-state issues: workspace selection could leave stale sync status behind, and `sync.force` blocked instead of returning `running` per `docs/backend-contract.md`.
- Addressed the blind-review findings by resetting sync status on workspace selection, running `sync.force` in a background worker with duplicate-run protection, invalidating old sync completions with a token, and polling `sync.status` from the SwiftUI force-sync path.
- Blind-review fix validation passed: `/opt/homebrew/bin/python3 -m unittest discover -s Tests` ran 42 tests, `/opt/homebrew/bin/python3 Scripts/python_coverage.py` reported 416/455 lines (91.4%), `swift build` passed, `swift test --enable-code-coverage` ran 11 tests, and `git diff --check` passed.
- PR #9 blind-review fixes were pushed and GitHub Actions `Test` passed on the updated branch.
- Second fresh blind review of PR #9 found no code-level bugs or contract regressions, but flagged that sync process-boundary behavior needed a real subprocess JSONL test because docs claimed subprocess coverage.
- Added `Tests/test_backend_helper_process.py` coverage for one long-lived helper process handling `sync.force` followed by `sync.status` polling.
- Second blind-review fix validation passed: `/opt/homebrew/bin/python3 -m unittest discover -s Tests` ran 43 tests, `/opt/homebrew/bin/python3 Scripts/python_coverage.py` reported 416/455 lines (91.4%), `swift test --enable-code-coverage` ran 11 tests, and `git diff --check` passed.
- PR #9 second blind-review fix was pushed and GitHub Actions `Test` passed on the updated branch.
- Third fresh blind review of PR #9 found no actionable bugs, regressions, contract drift, concurrency issues, missing required tests, or planning-doc drift.
- Added the next SwiftUI workflow coverage checkpoint to `docs/testing.md`: extract app workflow logic behind a testable seam, fake the backend client, and cover refresh, workspace selection, force-sync polling, task actions, detail-pane action availability, and shared sync command wiring.
- PR #9 was marked ready and merged into `feature/mac-prototype`.
- Fast-forwarded local `feature/mac-prototype` after PR #9 and created `codex/swiftui-workflow-coverage`.
- Added `AgendumMacWorkflow`, a SwiftPM target for app workflow state separate from backend process/client code.
- Moved `TaskItem`, `TaskSource`, and `BackendStatusModel` out of the SwiftUI executable into `Sources/AgendumMacWorkflow/TaskWorkflowModel.swift`.
- Added `AgendumBackendServicing` and fake-backed workflow tests for refresh, workspace selection, force-sync polling, task actions, action failure behavior, and detail-pane action availability.
- Wired the app menu `Sync Now` command and toolbar sync button through the same shared `BackendStatusModel.forceSync()` path.
- Local validation for the workflow checkpoint currently passes: `swift build`, `swift test --enable-code-coverage` with 22 Swift tests, `/opt/homebrew/bin/python3 -m unittest discover -s Tests` with 43 Python tests, `/opt/homebrew/bin/python3 Scripts/python_coverage.py` at 416/455 lines (91.4%), and `git diff --check`.
- Opened draft PR #10: `https://github.com/danseely/agendum-mac/pull/10`.
- GitHub Actions `Test` is passing on PR #10 at the time of this update.
- Addressed PR #10 review feedback: restructured `testRefreshFailureClearsTasksAndSurfacesError` so a successful refresh populates tasks before the failing refresh proves the catch's tasks clear, and expanded the 2026-05-02 entry in `docs/decisions.md` to name `AgendumBackendServicing` and `TaskDashboardCommands` alongside the `AgendumMacWorkflow` target.
- PR #10 was marked ready and merged into `feature/mac-prototype` after passing CI and a clean local review pass.
- Fast-forwarded local `feature/mac-prototype` after PR #10 and created the next short-lived branch for the manual task creation UX checkpoint.
- Implemented `task.createManual` in `Backend/agendum_backend/helper.py` delegating to `agendum.task_api.create_manual_task`, with title/project/tags payload validation that rejects blank strings and non-string tag entries.
- Added backend unit tests in `Tests/test_backend_helper.py` for full payload, minimal payload, selected-namespace DB usage, and invalid payloads.
- Added a subprocess JSONL test in `Tests/test_backend_helper_process.py` that creates a manual task, lists tasks through the same helper process, and verifies invalid payloads return enveloped errors.
- Added `createManualTask(title:project:tags:)` to `Sources/AgendumMacCore/BackendClient.swift` with a request payload that omits nil `project`/`tags` keys, and added a request/response Swift client test.
- Added `createManualTask(...)` to `BackendStatusModel` plus `AgendumBackendServicing`, with fake-backed workflow tests covering success/reload and failure-keeps-existing-tasks behavior.
- Wired a SwiftUI "New Task" toolbar button and `CreateManualTaskSheet` form that submits through `BackendStatusModel.createManualTask` and dismisses only on success.
- Committed the manual task creation checkpoint as `9a1239f`, pushed `codex/manual-task-creation` to `origin`, and opened draft PR #11 (`https://github.com/danseely/agendum-mac/pull/11`) against `feature/mac-prototype`.
- PR #11 was merged into `feature/mac-prototype` on 2026-05-02 (squash merge `1e8306a`).
- Fast-forwarded local `feature/mac-prototype` after the PR #11 merge and created `codex/per-task-error-surfacing` from the updated tip.
- Added `@Published taskActionErrors: [TaskItem.ID: String]` and `errorForTask(id:)` to `BackendStatusModel` in `Sources/AgendumMacWorkflow/TaskWorkflowModel.swift`.
- Routed task-action failures (`markSeen`, `markReviewed`, `markInProgress`, `moveToBacklog`, `markDone`, `removeTask`) into the per-task map via a now-task-aware `performTaskAction(taskID:)` instead of the global `errorMessage`.
- Wired `refresh()` and `selectWorkspace(...)` to clear the whole `taskActionErrors` map; successful task actions clear only the affected task's entry.
- Surfaced the per-task error inline in `TaskDetail` (`Sources/AgendumMac/AgendumMacApp.swift`) with a red caption under the action buttons.
- Updated `Tests/AgendumMacWorkflowTests/TaskWorkflowModelTests.swift`: replaced the single failure test with `testTaskActionFailureScopesErrorToTaskAndKeepsGlobalErrorClean`, added `testTaskActionSuccessClearsExistingPerTaskError`, `testTaskActionFailureOnOneTaskDoesNotClearAnotherTasksError`, `testRefreshClearsTaskActionErrors`, and `testSelectWorkspaceClearsTaskActionErrors`; added `taskActionErrors.isEmpty` assertion to `testTaskActionsCallBackendAndReloadTasks`.
- PR #12 (per-task error surfacing) merged into `feature/mac-prototype` on 2026-05-02 (squash merge `9edb428`).
- Created `codex/sync-lifecycle-presentation` from the post-PR-#12 tip of `feature/mac-prototype` for the richer sync lifecycle and structured error presentation checkpoint.
- PR #13 (sync lifecycle + structured error presentation) merged into `feature/mac-prototype` on 2026-05-02 (squash merge `30d66d4`).
- Created `codex/structured-error-mapping` from the post-PR-#13 tip of `feature/mac-prototype` for the structured-error-mapping checkpoint.
- PR #14 (structured error mapping) was marked ready and merged into `feature/mac-prototype` on 2026-05-02 (squash merge `e05efa7`).
- Fast-forwarded local `feature/mac-prototype` to `e05efa7` and created `codex/packaging-matrix-doc` from the updated tip for the packaging-matrix doc checkpoint.
- PR #15 (packaging matrix doc) merged into `feature/mac-prototype` on 2026-05-02 (squash merge `3e4e34a`).
- Fast-forwarded local `feature/mac-prototype` to `3e4e34a` and created `codex/app-bundle-smoke` from the updated tip for the unsigned `.app` bundle smoke checkpoint.
- PR #16 (unsigned `.app` smoke bundle) merged into `feature/mac-prototype` on 2026-05-03 (squash merge `12cf468`).
- Fast-forwarded local `feature/mac-prototype` to `12cf468` and pruned the merged `codex/app-bundle-smoke` and earlier merged `codex/*` remote refs.
- PR #17 (item 1 — open task URL detail action) merged into `feature/mac-prototype` on 2026-05-03 (squash merge `c2a6d97`). Item 1 of the five-item orchestration in `docs/orchestration-plan.md` is complete; the detail-pane "Open in Browser" action now routes through `BackendStatusModel.openTaskURL(id:)` with structured per-task error reporting and an injectable `URLOpening` seam. The PR also included an in-scope drive-by fix to `BackendClientConfiguration.firstAncestor` that resolved an infinite-loop bug introduced in PR #16.
- Fast-forwarded local `feature/mac-prototype` to `c2a6d97` after the PR #17 merge and created `codex/item-2-task-list-filtering` from the updated tip for the item-2 design phase.
- PR #18 (item 2 — task list filtering UI) merged into `feature/mac-prototype` on 2026-05-03 (squash merge `c29c630`). Item 2 of the five-item orchestration is complete; `BackendStatusModel` now owns filter state for `source`, `status`, `project`, `includeSeen`, and `limit`, the SwiftUI dashboard exposes filter controls with workspace-switch reset semantics, and fake-backed `AgendumMacWorkflowTests` cover filter routing through `loadTaskItems`.
- Fast-forwarded local `feature/mac-prototype` to `c29c630` after the PR #18 merge and created `codex/item-3-settings-auth-repair` from the updated tip for the item-3 design phase.
- PR #19 (item 3 — settings / auth-repair UI) merged into `feature/mac-prototype` on 2026-05-03 (squash merge `c4a6b5a`). Item 3 of the five-item orchestration is complete; `BackendStatusModel` now carries `diagnostics`/`diagnosticsError` state plus `refreshDiagnostics()` / `copyAuthLoginCommand()` / `openGHInstallURL()` actions, the helper has an `auth.diagnose` command surface and a shared `_format_repair_command` formatter for the repair string, and `AgendumMacApp.swift`'s `Settings { SettingsView() }` scene displays gh status / auth status / helper PATH / repair actions.
- Fast-forwarded local `feature/mac-prototype` to `c4a6b5a` after the PR #19 merge and created `codex/item-4-shortcuts-menus` from the updated tip for the item-4 design phase.
- PR #20 (item 4 — keyboard shortcuts + menu coverage) merged into `feature/mac-prototype` on 2026-05-03 (squash merge `158954c`). Item 4 of the five-item orchestration is complete; the menu bar now exposes File menu shortcuts (`Cmd-N` New Task, `Cmd-R` Refresh, `Cmd-Shift-S` Sync Now — relocated from the prior `Cmd-R`) and a new top-level `Task` menu with per-task actions (`Cmd-Shift-L` Open in Browser, `Cmd-Opt-{M,R,I,B,D}` for the per-task state actions, `Cmd-Shift-Backspace` Remove). The `TaskDashboardCommand` enum was extended with the new cases, a `selectedTaskID` mirror seam was added to `BackendStatusModel`, and the App-level `@State` for `selectedTask` and `isShowingCreateManualTask` was lifted from `TaskDashboardView` to `AgendumMacApp` so the `.commands { ... }` closure can read and write them.
- Fast-forwarded local `feature/mac-prototype` to `158954c` after the PR #20 merge and created `codex/item-5-notifications-badge` from the updated tip for the item-5 design phase.
- PR #21 (item 5 — notifications + dock badge for sync results) merged into `feature/mac-prototype` on 2026-05-03 (squash merge `4172378`). Item 5 of the five-item orchestration is complete.
- Fast-forwarded local `feature/mac-prototype` to `4172378` after the PR #21 merge.
- Five-item live-slice orchestration COMPLETE on 2026-05-03. Total tests added across the orchestration: Swift suite grew 45 → 119; Python suite grew 48 → 61; backend coverage 91.9% → 92.4%.
- A1 (`@Observable` migration, issue #27) implementation landed on `codex/a1-observable-migration`: `BackendStatusModel` is now `@Observable @MainActor public final class` with no `@Published` / `ObservableObject` / `Combine` import; `AgendumMacApp.swift` uses `@State` / `@Environment(BackendStatusModel.self)` / plain stored properties for the model; all 119 Swift tests, 61 Python tests, `swift build`, `swift run AgendumMac` smoke launch, and `git diff --check` pass on the branch.

## In progress
- Planning-doc PR **#23** (`codex/standalone-architecture-planning`) is open against `feature/mac-prototype`, capturing the 2026-05-03 plan revision: `docs/research/{backend-engine,data-store,architecture,synthesis,proposed-issues}.md` and updates to `docs/plan.md`, `docs/decisions.md`, `docs/status.md`, `docs/handoff.md`.
- Three epic tracking issues filed: **#24** (Architecture modernization), **#25** (Standalone backend engine), **#26** (Native data store).
- A1 leaf issue **#27** filed; PR for `codex/a1-observable-migration` open against `feature/mac-prototype` (URL recorded in `docs/handoff.md`).

## Blocked
- None at the implementation level. Phase 1 work (A1, A2, B1) is unblocked once PR #23 merges. Leaf issues for each phase are filed when work begins (per user's instruction to file leaves as the phase approaches; drafts in `docs/research/proposed-issues.md`).

## Next
1. Merge PR #23 after review.
2. File leaf issue A1 (`@Observable` migration) and start it on `codex/a1-observable-migration`. Optionally parallel: A2 (`os.Logger`) on `codex/a2-os-logger`, B1 (fork-and-vendor) on `codex/b1-fork-and-vendor`. A1 is the highest priority because it's a one-PR foundation that simplifies every later slice.
3. Keep CI aligned with local validation as new test layers are added; keep `main` README-only; keep `feature/mac-prototype` as the integration branch and use short-lived `codex/*` branches.
