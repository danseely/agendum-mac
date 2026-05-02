# Decisions

## 2026-04-28
- Decision: Create a separate local `agendum-mac` project for GUI work.
- Reason: The GUI exploration should not churn the existing terminal CLI repo.
- Impact: Planning docs and Mac app scaffold live here; `../agendum` remains the backend/reference source.
- Plan change: yes; the earlier planning docs were moved out of `../agendum`.

## 2026-04-28
- Decision: Treat the first macOS effort as a native shell around the existing Python engine, pending prototype validation.
- Reason: The current agendum code already separates core task storage, sync, and GitHub status logic from the Textual UI enough to avoid an immediate rewrite.
- Impact: Early GUI work should focus on a backend contract and Mac-native UX rather than porting all domain logic to Swift.
- Plan change: no; this records the initial evaluation direction.

## 2026-04-28
- Decision: Use a Swift Package scaffold first, not a hand-authored Xcode project.
- Reason: It gives us a local SwiftUI app shell without brittle manual `.pbxproj` maintenance.
- Impact: A generated Xcode project or standard Xcode app template can be introduced once the prototype shape is clearer.
- Plan change: no.

## 2026-04-28
- Decision: Use a JSON-over-stdio helper process as the default bridge for the first live prototype.
- Reason: It keeps Swift and Python process-isolated, avoids direct Swift/Python embedding risk, and gives the Mac app a narrow contract it can own.
- Impact: The next planning artifact is `docs/backend-contract.md`; MCP remains assistant-facing/reference material unless a later decision changes this.
- Plan change: yes; this narrows the bridge choice before implementation.

## 2026-04-28
- Decision: Build a full windowed task dashboard before any menu bar helper.
- Reason: The existing product is a dashboard with grouped task triage, actions, sync status, and workspace context; the first Mac prototype should preserve that workflow.
- Impact: Menu bar behavior, notifications, and state restoration are deferred until the live windowed vertical slice works.
- Plan change: no.

## 2026-04-28
- Decision: The backend helper should own SQLite access for the prototype.
- Reason: The CLI and Mac app may run concurrently against the same workspace data, and keeping DB access behind one service boundary reduces concurrency and schema drift risk.
- Impact: Swift should call helper commands instead of reading or writing the SQLite database directly.
- Plan change: yes; this constrains the first backend design.

## 2026-04-28
- Decision: Accept `docs/backend-contract.md` for the first implementation pass.
- Reason: A fresh independent review found the revised contract clean after adding sync semantics, concrete schemas, URL metadata, workspace defaults, auth/PATH behavior, and helper-owned SQLite rules.
- Impact: Implementation can begin with the backend helper target/adapter using the accepted v0 JSON-over-stdio contract.
- Plan change: no.

## 2026-04-28
- Decision: Use stacked branches for the public prototype workflow.
- Reason: README-only `main` should stay minimal until the prototype is ready, while implementation checkpoints need reviewable branches that do not all target `main` directly.
- Impact: `feature/mac-prototype` is the broad integration branch off `main`; narrower branches such as `feature/backend-helper` target it.
- Plan change: yes; this replaces direct implementation PRs against `main` with a stacked PR workflow.

## 2026-04-28
- Decision: Treat testing as a milestone gate throughout the Mac prototype, starting with backend helper unit and subprocess tests before further feature work.
- Reason: The riskiest parts of the MVP are the Python helper boundary, workspace/auth behavior, sync lifecycle, and Swift-to-helper integration; adding coverage as each boundary appears keeps regressions cheaper than adding broad tests after the live slice.
- Impact: `docs/testing.md` is now canonical for test expectations, and future implementation checkpoints should update planning docs with validation commands and results.
- Plan change: yes; this adds explicit test gates to the prototype plan.

## 2026-04-28
- Decision: Start backend coverage reporting with a stdlib-based local script instead of adding `coverage.py` immediately.
- Reason: The repo does not yet have Python dependency management, and the first reporting need is a lightweight helper coverage summary that runs with the existing toolchain. This is not the long-term Mac app coverage approach.
- Impact: `python3 Scripts/python_coverage.py` reports in-process line coverage for `Backend/agendum_backend/helper.py`; subprocess entrypoint behavior remains covered by integration tests rather than line-counted. Swift coverage should use `swift test --enable-code-coverage` while the repo is SwiftPM-only, and `xcodebuild test -enableCodeCoverage YES` / `xccov` after an Xcode app project exists.
- Plan change: yes; this adds coverage reporting as part of the testing baseline.

## 2026-04-28
- Decision: Add GitHub Actions CI for the current local validation pipeline on macOS.
- Reason: The testing baseline should run on every PR instead of relying only on local handoff validation.
- Impact: CI checks out `agendum-mac` and sibling `agendum`, then runs Python helper coverage, Python unit/integration tests, `swift build`, and `git diff --check`. The sibling checkout is temporary until the backend dependency is formalized.
- Plan change: yes; CI becomes part of the testing baseline.

## 2026-04-28
- Decision: Treat `feature/mac-prototype` as a clean integration branch that is updated through PRs, not direct pushes.
- Reason: The prototype branch is the primary shared integration surface and should stay reviewable through stacked PRs.
- Impact: Future changes should be made on short-lived branches and opened as PRs targeting `feature/mac-prototype`; direct pushes require explicit user approval.
- Plan change: yes; this tightens the stacked branch workflow.

## 2026-04-30
- Decision: Add a testable Swift core target for backend-helper process wiring, and use the checked-out Python helper for SwiftPM development runs.
- Reason: The Mac app needs a narrow Swift client before task data can replace sample data, and the current prototype is still repo-local rather than packaged.
- Impact: `AgendumMacCore` owns request/response decoding and the long-lived helper process. Development runs prefer common Homebrew Python paths before `/usr/bin/python3` because the helper depends on Python 3.11+ `tomllib`.
- Plan change: no; this implements the accepted JSON-over-stdio bridge for the SwiftPM prototype and leaves production packaging unresolved.

## 2026-04-30
- Decision: Merge the Swift helper-process client checkpoint through PR #5 after review fixes and passing CI.
- Reason: The checkpoint establishes the first tested Swift-to-helper boundary, addresses process timeout/lifecycle review findings, and keeps SwiftPM coverage in CI.
- Impact: `feature/mac-prototype` will contain the Swift helper client and the next short-lived branch can focus on workspace selection or backend-backed task loading.
- Plan change: no; this advances the accepted JSON-over-stdio bridge implementation.

## 2026-05-02
- Decision: Add a separate `AgendumMacWorkflow` target for app workflow state, an `AgendumBackendServicing` protocol so workflow tests can fake the backend, and a `TaskDashboardCommands` command type so toolbar and menu sync share one code path, instead of putting any of this in `AgendumMacCore`.
- Reason: `AgendumMacCore` should stay focused on helper protocol models and process-boundary client behavior, while refresh, workspace switching, sync polling, task actions, and detail action availability are app workflow concerns that need fake-backed tests.
- Impact: The executable imports `AgendumMacWorkflow` and consumes both the protocol-typed model and `TaskDashboardCommands.standard`; workflow tests inject `AgendumBackendServicing` fakes without launching SwiftUI or spawning the Python helper.
- Plan change: no; this implements the SwiftUI workflow coverage checkpoint already recorded in `docs/testing.md`.

## 2026-05-02
- Decision: Add `task.createManual` to the v0 helper contract behind the existing `agendum.task_api.create_manual_task`, encode optional `project`/`tags` on the Swift side using `encodeIfPresent` (omit nil keys), and expose a `BackendStatusModel.createManualTask(...)` returning `Bool` so the SwiftUI sheet can dismiss only on success.
- Reason: Manual task creation is the next live-slice gap named in `docs/plan.md`; reusing `agendum.task_api.create_manual_task` keeps source/status defaults consistent with the CLI, and the `Bool` return separates form lifecycle (dismiss) from status presentation (`errorMessage`) without requiring the SwiftUI form to inspect helper errors directly.
- Impact: The helper accepts both omitted and explicit-`null` `project`/`tags` (matching existing `_optional_*` validation patterns), the workflow target gains `createManualTask` plumbing covered by fake-backed tests, and the dashboard exposes a "New Task" toolbar button that opens a sheet for title/project/tags entry.
- Plan change: no; this implements the manual task creation checkpoint already named in `docs/plan.md` and `docs/handoff.md`.
