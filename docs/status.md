# Status

Last updated: 2026-05-02

## Current milestone
Manual task creation UX is implemented on `codex/manual-task-creation`. The next short-lived branch from updated `feature/mac-prototype` should pick up any remaining live-slice gap once this checkpoint merges.

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

## In progress
- None. The manual task creation UX checkpoint is implemented and validated locally on `codex/manual-task-creation`; opening a draft PR against `feature/mac-prototype` is the next external action.

## Blocked
- None.

## Next
- Push `codex/manual-task-creation` and open a draft PR against `feature/mac-prototype`.
- Run blind PR review and address findings before marking ready.
- Keep CI aligned with local validation as new test layers are added.
- Keep `main` README-only until the prototype is ready.
- Use short-lived branches and PRs for all changes targeting `feature/mac-prototype`.
- Keep `feature/mac-prototype` as the broad integration branch.
