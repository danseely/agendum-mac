# Testing Plan

## Goal
Keep test coverage aligned with the prototype risks as the app moves from sample data to a live Mac vertical slice.

The highest-risk areas are the helper protocol, workspace/auth behavior, task mutation semantics, sync lifecycle, and Swift-to-helper process integration. UI tests should start small and focus on Mac workflows once the UI is backed by real helper data.

## Coverage Layers

### Backend Unit Tests
Use focused Python tests for helper command handlers and service-layer behavior.

Must cover as commands are added:
- protocol envelope validation, unsupported versions, unknown commands, malformed payloads, and non-object requests
- workspace current/list/select behavior, including base workspace and namespace paths
- auth status for missing `gh`, unauthenticated `gh`, authenticated `gh`, and username lookup failure
- task list/search/get/create payload mapping from agendum storage into bridge schema
- task actions: mark reviewed, mark in progress, move to backlog, mark done, remove, and mark seen
- sync force/status state transitions, duplicate sync requests, terminal errors, and event/polling semantics
- stable error codes and user-presentable recovery text

### Backend Integration Tests
Use subprocess tests against `Backend/agendum_backend_helper.py` to verify the actual JSONL process boundary.

Must cover:
- one request/one response framing
- multiple sequential requests in one helper process
- malformed input recovery, where the helper continues after returning an error envelope
- environment handling for `AGENDUM_MAC_BASE_DIR`, `AGENDUM_MAC_GH_PATHS`, and `GH_CONFIG_DIR`
- fixture-backed task storage once task commands are implemented

### Coverage Reporting
Use coverage reporting that matches the layer under test.

Current Python helper scope:
- use `python3 Scripts/python_coverage.py` as a temporary helper-only report
- reports stdlib line coverage for `Backend/agendum_backend/helper.py`
- runs the full Python unittest suite before reporting
- treats subprocess-entrypoint behavior as integration-tested but not line-counted
- avoids adding a third-party coverage dependency until the project has package/dependency management

Intended Swift app scope:
- use `swift test --enable-code-coverage` while the app remains SwiftPM-only
- inspect SwiftPM coverage through the generated LLVM coverage artifacts
- add Swift coverage reporting once helper-client code exists outside SwiftUI views

Future Xcode app scope:
- when the project moves to an Xcode app/scheme, use `xcodebuild test -enableCodeCoverage YES`
- inspect or export coverage from the `.xcresult` bundle with `xccov`
- keep Mac app validation tied to normal app workflows, including launch, Settings, menus, keyboard navigation, and window resizing

Revisit once dependency management and CI are in place:
- switch Python helper reporting to `coverage.py` if subprocess coverage, HTML reports, XML/CI output, or branch coverage becomes useful
- add minimum coverage thresholds only after backend command and Swift helper-client coverage stabilizes

### CI Pipeline
Use GitHub Actions to run the current local validation pipeline on macOS.

Current CI shape:
- check out `danseely/agendum-mac`
- check out `danseely/agendum` as a sibling directory because the helper currently bootstraps imports from `../agendum/src`
- run `python3 Scripts/python_coverage.py`
- run `python3 -m unittest discover -s Tests`
- run `swift build`
- run `git diff --check`

CI should stay aligned with the local handoff validation. When new test layers are added, update the workflow in the same checkpoint as the tests.

Later updates:
- add `swift test --enable-code-coverage` once Swift test targets exist
- export Xcode coverage with `xccov` once there is an Xcode app project or scheme
- replace the sibling checkout with package/dependency setup once the backend dependency is formalized

### Swift Unit Tests
Add Swift tests once helper-client code is separated from SwiftUI views.

Must cover:
- request encoding and response decoding
- backend error mapping into UI-facing state
- task/workspace/auth/sync model decoding
- helper process lifecycle decisions that can be tested without launching the full app

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
- helper discovery from a Finder-launched app
- `gh` discovery and auth repair path outside a terminal environment
- signing, hardened runtime, notarization, sandbox, and privacy manifest requirements for the chosen channel

## Milestone Gates

## Immediate Test Checkpoint
Before adding more backend commands or Swift helper wiring, establish the helper boundary baseline.

Scope:
- Add subprocess JSONL tests for `Backend/agendum_backend_helper.py`.
- Add missing helper protocol edge-case unit tests.
- Keep the checkpoint limited to the existing commands: `workspace.current` and `auth.status`.
- Do not add Swift tests until helper-client code exists outside SwiftUI views.

Acceptance:
- `python3 -m unittest discover -s Tests` passes.
- `swift build` passes.
- `git diff --check` passes.
- `docs/status.md` and `docs/handoff.md` record the completed validation.

### Before Swift Helper Wiring
- Keep `swift build` passing.
- Keep Python unit tests passing.
- Add subprocess JSONL integration tests for the helper entrypoint.
- Add missing protocol edge-case tests for bad payloads and unknown commands.
- Run temporary helper coverage with `python3 Scripts/python_coverage.py` and record the result in `docs/handoff.md`.
- Keep the GitHub Actions test workflow aligned with these local checks.

### Before Adding Each New Backend Command
- Add or update contract examples in `docs/backend-contract.md`.
- Add unit tests for success, invalid payload, and expected failure states.
- Add subprocess coverage when the command crosses environment or process-boundary behavior.

### Before Replacing Sample Data
- Add fixture-backed task tests for list/search/get.
- Add Swift model decoding tests for task payloads.
- Add helper-client tests using fake stdio or a controllable subprocess wrapper.
- Start SwiftPM coverage reporting with `swift test --enable-code-coverage` once Swift tests exist.

### Before Task Mutations
- Add backend tests proving each mutation changes storage as expected.
- Add idempotency or not-found behavior tests.
- Verify returned task payloads match the bridge schema.

### Before Sync UI
- Add tests for sync status state transitions and duplicate `sync.force`.
- Add at least one terminal-error case that maps to a stable error code and recovery message.

### Before Calling The Prototype Ready
- `swift build` passes.
- Python unit and integration tests pass.
- Swift tests pass.
- Swift coverage reporting is available through SwiftPM or Xcode, depending on project shape.
- `swift run AgendumMac` has been manually smoke-tested.
- The live app can load, sync, show errors, open URLs, and perform core task actions.
- `docs/status.md` and `docs/handoff.md` record the validation run.
