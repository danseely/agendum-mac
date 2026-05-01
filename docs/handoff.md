# Handoff

## Current objective
Prepare the next live-slice checkpoint after backend-backed task list loading landed.

## Branch
`feature/mac-prototype`

## Repo state
- HEAD: `feature/mac-prototype`; run `git rev-parse --short HEAD` for the exact commit.
- Integration branch: `feature/mac-prototype` at squash merge `8e71589`.
- Current base checkpoint PR: `https://github.com/danseely/agendum-mac/pull/6`, merged into `feature/mac-prototype` on 2026-05-01.
- Task-list PR: `https://github.com/danseely/agendum-mac/pull/7`, merged into `feature/mac-prototype` on 2026-05-01.
- Post-merge docs update: PR #8 records the PR #7 merge state.
- Remote: `origin` = `git@github.com:danseely/agendum-mac.git`
- PR #1: `https://github.com/danseely/agendum-mac/pull/1`, merged into `feature/mac-prototype`
- PR #3: `https://github.com/danseely/agendum-mac/pull/3`, merged into `feature/mac-prototype`
- PR #4: `https://github.com/danseely/agendum-mac/pull/4`, merged into `feature/mac-prototype`
- PR #5: `https://github.com/danseely/agendum-mac/pull/5`, merged into `feature/mac-prototype`
- PR #6: `https://github.com/danseely/agendum-mac/pull/6`, merged into `feature/mac-prototype`
- Parent PR #2: `https://github.com/danseely/agendum-mac/pull/2`, draft, targeting `main`
- Local cleanup: deleted local `codex/test-coverage-reporting`, `feature/backend-helper`, and `codex/document-branch-discipline` branches after merge.
- Branch discipline: do not push directly to `feature/mac-prototype`; use short-lived branches and PRs targeting `feature/mac-prototype` unless explicitly requested otherwise.
- Working tree: should be clean after PR #8 lands.
- Last validation date: 2026-05-01

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

## Validation
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
- Pending: `swift run AgendumMac`.

## Changed files
- `Backend/agendum_backend/helper.py`
- `Sources/AgendumMacCore/BackendClient.swift`
- `Sources/AgendumMac/AgendumMacApp.swift`
- `Tests/AgendumMacCoreTests/BackendClientTests.swift`
- `Tests/test_backend_helper.py`
- `Tests/test_backend_helper_process.py`
- `docs/plan.md`
- `docs/status.md`
- `docs/handoff.md`

## Risks / blockers
- A Mac App Store build is likely harder if the app depends on launching external `gh` and sharing `gh` auth files.
- The current agendum MCP/task API is read/create-heavy and does not yet expose all actions the GUI needs.
- Packaging Python plus dependencies inside a signed app needs explicit design.
- Finder-launched apps do not inherit shell `PATH`, so `gh` discovery cannot assume the terminal environment.
- SwiftPM development runs now prefer common Homebrew Python paths, but the production helper runner and bundled Python strategy are still unresolved.
- Current `gh auth login` flow is terminal-oriented and needs Mac-specific repair UX.
- SQLite ownership must stay behind the helper unless a later decision permits direct Swift DB access.

## Next actions
1. Start a short-lived branch for task detail refresh, task actions, and sync wiring.
2. Keep `feature/mac-prototype` as the broad integration branch and continue landing work through PRs.
3. Keep the manual `swift run AgendumMac` smoke test in mind before treating the UI slice as fully exercised.

## After checkpoint
- Continue from backend-backed `task.list` loading to task detail refresh, task actions, and sync wiring.

## Drift from original plan
- Approved deviation: GUI work moved from `../agendum` into this standalone project.
- Approved deviation: public `main` is README-only; prototype work lives on stacked feature branches.
- Resolved stack state: `codex/task-list-loading` was temporarily based on PR #6, then rebased onto `feature/mac-prototype` after PR #6 merged.
