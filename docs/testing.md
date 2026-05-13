# Testing Plan

## Goal
Keep test coverage aligned with the prototype risks as the app moves from sample data to a live Mac vertical slice.

The highest-risk areas are native workspace/auth behavior, task mutation semantics, sync lifecycle, GitHub transport behavior, and Swift app-service integration. UI tests should start small and focus on Mac workflows once the UI is backed by live native services.

## Coverage Layers

### Python Parity Tests
Use focused Python tests only as a parity oracle for retained reference code and fixtures.

Current scope:
- `Tests/test_gh_status_derivation.py` characterizes original CLI status derivation against the shared fixture.
- `Backend/agendum_engine/` remains in-tree as a post-cutover parity reference, not runtime app code.
- No Python helper subprocess or JSONL bridge tests remain after S3+S4 app cutover.

### Coverage Reporting
Use coverage reporting that matches the layer under test.

Current Swift app scope:
- use `swift test --enable-code-coverage` while the app remains SwiftPM-only
- inspect SwiftPM coverage through the generated LLVM coverage artifacts
- keep Python parity tests as pass/fail characterization, not line-coverage gates

Future Xcode app scope:
- when the project moves to an Xcode app/scheme, use `xcodebuild test -enableCodeCoverage YES`
- inspect or export coverage from the `.xcresult` bundle with `xccov`
- keep Mac app validation tied to normal app workflows, including launch, Settings, menus, keyboard navigation, and window resizing

Revisit once Swift coverage has stabilized:
- add minimum coverage thresholds only after native service, store, sync, and workflow coverage stabilizes

### CI Pipeline
Use GitHub Actions to run the current local validation pipeline on macOS.

Current CI shape:
- check out `danseely/agendum-mac`
- run for all pull requests
- run for direct pushes to `main`
- run `python3 -m unittest discover -s Tests` for parity tests
- run `swift build`
- run `swift test --enable-code-coverage`
- run `Scripts/build_app_bundle.sh` plus bundle existence/plist checks
- run `jq empty docs/features.json`
- run stale helper/runtime reference checks over `.github Scripts docs/testing.md Package.swift Sources Tests`
- run `git diff --check`

CI should stay aligned with the local handoff validation. When new test layers are added, update the workflow in the same checkpoint as the tests.

Later updates:
- export Xcode coverage with `xccov` once there is an Xcode app project or scheme

### Swift Unit Tests
Add Swift tests for native service, transport, store, sync, model, and command behavior.

Must cover:
- GitHub request encoding, response decoding, rate-limit/auth behavior, and retry semantics
- native workspace/auth/sync service behavior
- app-service error mapping into UI-facing state
- task/workspace/auth/sync model decoding
- store and sync behavior without launching the full app

### SwiftUI Workflow Unit Tests
Before adding broad UI automation, move workflow logic behind a testable seam so SwiftPM tests can cover behavior without launching the app.

Current shape:
- `DashboardModel` lives in `AgendumFeature`.
- `DashboardServicing` fakes drive workspace, auth, sync, task-list, and task-action responses without spawning subprocesses.
- SwiftUI view code stays thin: views call model methods or command descriptors, while state transitions and available action decisions live in testable Swift code.

Must cover:
- `refresh()` success and failure: workspace, workspace list, auth, sync, task loading, task clearing on failure, and user-presentable error state.
- `selectWorkspace(id:)`: no-op for the current workspace, successful workspace/auth/sync/task replacement, task clearing during reload, and failure behavior.
- `forceSync()`: starts sync, polls `sync.status` while state is `running`, stops on idle/error, reloads tasks after terminal state, and handles polling/transport errors.
- Task actions: mark seen, mark reviewed, mark in progress, move to backlog, mark done, and remove all call the expected backend method, refresh tasks afterward, and surface errors without corrupting current task state.
- Detail-pane action availability: review tasks show review actions, backend `manual` tasks show manual status actions, GitHub issue rows do not get manual-only status actions, URL actions require a URL, and remove remains available where intended.
- Shared app commands: toolbar sync and the app menu sync command should reach the same model action once the menu command is wired.

Acceptance:
- New SwiftPM tests run under `swift test --enable-code-coverage`.
- No Python helper process is needed for workflow tests.
- Manual launch smoke remains useful, but it should no longer be the only coverage for force-sync polling and detail-pane task actions.

### Swift UI / App Validation
Use manual app validation initially, then add UI automation when the live slice is stable.

Must validate:
- `swift run AgendumMac` launches the app
- the app works at small and large window sizes
- sidebar/list/detail selection behaves normally with keyboard and pointer input
- Settings opens with `Cmd-,`
- Sync command, toolbar button, and menu item reach the same app action
- backend errors are visible and recoverable
- browser opening remains owned by the Mac app

### Release / Packaging Tests
Defer until a distribution channel is chosen.

Before release planning, validate:
- `gh` discovery and auth repair path outside a terminal environment
- signing, hardened runtime, notarization, sandbox, and privacy manifest requirements for the chosen channel

## Milestone Gates

## Current Test Checkpoint
Before publishing S3+S4 app-cutover work, keep the helper-free runtime gates green.

Scope:
- Native app services own workspace/auth/sync status and `SyncEngine` composition.
- `DashboardModel` workflow tests use `DashboardServicing` fakes and `TaskStoreProviding` fakes.
- Python tests are parity-only.

Acceptance:
- `swift build` passes.
- `swift test --enable-code-coverage` passes.
- `python3 -m unittest discover -s Tests` passes.
- `Scripts/build_app_bundle.sh` passes.
- `jq empty docs/features.json` passes.
- `git diff --check` passes.
- stale helper/runtime grep over `.github Scripts docs/testing.md Package.swift Sources Tests` returns no matches.
- `docs/project-state.md` and `docs/features.json` record completed validation.

### Before Adding Each New Native Service Method
- Add or update contract examples only when the method crosses a module or app-service boundary that needs a documented payload.
- Add unit tests for success, invalid payload, and expected failure states.
- Add process-boundary coverage only for behavior that still shells out intentionally, such as `gh` auth discovery.

### Before Expanding Native Task Data
- Add fixture-backed task tests for list/search/get.
- Add Swift model decoding tests for task payloads.
- Keep `DashboardServicing` and `TaskStoreProviding` fake coverage aligned with the new fields.

### Before Task Mutations
- Add store/service tests proving each mutation changes storage as expected.
- Add idempotency or not-found behavior tests.
- Verify returned task payloads match the Swift model contract.

### Before Sync UI
- Add tests for sync status state transitions and duplicate `sync.force`.
- Add at least one terminal-error case that maps to a stable error code and recovery message.

### Before Deepening UI Features After PR #9
- Add the SwiftUI workflow unit-test seam described above before adding more task detail behavior, manual task creation UX, richer sync presentation, keyboard shortcuts, or menu command wiring.
- Cover force-sync polling and detail-pane task actions in SwiftPM tests before relying on manual smoke tests for future UI changes.
- Decide whether menu command wiring belongs in the same checkpoint; current app validation expects toolbar and menu sync commands to converge on the same action.

### Dashboard Interactions (Manual)
The task list selection model is a SwiftUI / `NSTableView` gesture composition that unit tests cannot fully exercise. Every dashboard PR that touches `Sources/AgendumMac/AgendumMacApp.swift` around `List(selection:)` must manually verify:

- **Single-click on a task row** selects + highlights the row (drives `selectedTask`).
- **Keyboard ↑/↓** navigates between visible rows and matches the click-selected state. With no current selection, the first ↑ or ↓ keystroke selects the first visible row; subsequent presses navigate normally.
- **Return / Space** with a selected row opens the task action modal.
- **Double-click on a task row** opens the task action modal.
- **Right-click (or two-finger tap) on a task row** shows a context menu with "Open actions…" that opens the same modal.
- **Inside the task action modal**, both **Space** and **Return** activate the focused action button; **Tab / Shift-Tab** moves focus between buttons; **Esc** closes. The first action is focused automatically on open.

Regression note: attaching `.simultaneousGesture(TapGesture(count: 2))` (or any per-row `TapGesture`) to rows inside `List(selection:)` on macOS swallows the single-click before `NSTableView` selection sees it — keyboard nav keeps working but click selection silently breaks. See issue #61. The fix is `List.contextMenu(forSelectionType:menu:primaryAction:)` at the **list level**: the `primaryAction` closure fires on double-click and Return without interfering with single-click selection because it lives on the List, not on each row. Use that API rather than per-row tap gestures.

### Before Calling The Prototype Ready
- `swift build` passes.
- Python unit and integration tests pass.
- Swift tests pass.
- Swift coverage reporting is available through SwiftPM or Xcode, depending on project shape.
- `swift run AgendumMac` has been manually smoke-tested.
- The live app can load, sync, show errors, open URLs, and perform core task actions.
- `docs/project-state.md` and `docs/features.json` record the validation run.
