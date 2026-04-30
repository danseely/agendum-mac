# Handoff

## Current objective
Review the Swift helper-process wiring checkpoint.

## Branch
`codex/swift-helper-client`

## Repo state
- HEAD: `codex/swift-helper-client`; run `git rev-parse --short HEAD` for the exact local commit.
- Integration branch: `feature/mac-prototype`
- Current sub-PR: `https://github.com/danseely/agendum-mac/pull/5`
- Current sub-PR target: `feature/mac-prototype`
- Remote: `origin` = `git@github.com:danseely/agendum-mac.git`
- PR #1: `https://github.com/danseely/agendum-mac/pull/1`, merged into `feature/mac-prototype`
- PR #3: `https://github.com/danseely/agendum-mac/pull/3`, merged into `feature/mac-prototype`
- PR #4: `https://github.com/danseely/agendum-mac/pull/4`, merged into `feature/mac-prototype`
- PR #5: `https://github.com/danseely/agendum-mac/pull/5`, draft, targeting `feature/mac-prototype`
- Parent PR #2: `https://github.com/danseely/agendum-mac/pull/2`, draft, targeting `main`
- Local cleanup: deleted local `codex/test-coverage-reporting`, `feature/backend-helper`, and `codex/document-branch-discipline` branches after merge.
- Branch discipline: do not push directly to `feature/mac-prototype`; use short-lived branches and PRs targeting `feature/mac-prototype` unless explicitly requested otherwise.
- Working tree: clean after pushing PR #5 docs follow-up.
- Last validation date: 2026-04-30

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
- Added `Tests/AgendumMacCoreTests/BackendClientTests.swift` covering real helper process requests and helper error mapping.
- Updated `.github/workflows/test.yml` so CI runs `swift test`.
- Recorded the development runner choice in `docs/decisions.md`: SwiftPM development runs use the checked-out helper and prefer common Homebrew Python paths before `/usr/bin/python3`; production packaging remains undecided.
- Opened draft PR #5 against `feature/mac-prototype`.

## Validation
- `swift build` passes.
- `swift test` passes: 2 Swift tests.
- `python3 -m unittest discover -s Tests` passes: 18 tests.
- `python3 Scripts/python_coverage.py` passes: 193/207 lines, 93.2% for `Backend/agendum_backend/helper.py`.
- Smoke-tested JSONL helper invocation with `workspace.current` and `auth.status`.
- `git diff --check` passes.
- `.github/workflows/test.yml` parses as YAML with Ruby's stdlib parser.
- GitHub Actions PR run `25076611284` passed for PR #3 before the checkout v5 update.
- GitHub Actions PR run `25076677868` passed for PR #3 after the checkout v5 update.
- GitHub Actions PR run `25076838730` passed for PR #3 after removing duplicate branch push triggers.
- GitHub Actions PR run `25077164616` passed for PR #3 after enabling all pull-request targets.
- GitHub Actions checks for parent PR #2 are passing after PR #3 merged into `feature/mac-prototype`.
- CI push triggers now exclude `feature/mac-prototype`; the parent PR handles validation for that branch.
- GitHub Actions PR run `25077788303` passed for PR #4.
- Pending: `swift run AgendumMac`.

## Changed files
- `.gitignore`
- `.github/workflows/test.yml`
- `Backend/agendum_backend/__init__.py`
- `Backend/agendum_backend/helper.py`
- `Backend/agendum_backend_helper.py`
- `Package.swift`
- `README.md`
- `Scripts/python_coverage.py`
- `Sources/AgendumMacCore/BackendClient.swift`
- `Sources/AgendumMac/AgendumMacApp.swift`
- `Tests/AgendumMacCoreTests/BackendClientTests.swift`
- `Tests/test_backend_helper.py`
- `Tests/test_backend_helper_process.py`
- `docs/plan.md`
- `docs/status.md`
- `docs/decisions.md`
- `docs/handoff.md`
- `docs/testing.md`
- `docs/mac-gui-port-evaluation.md`
- `docs/backend-contract.md`

## Risks / blockers
- A Mac App Store build is likely harder if the app depends on launching external `gh` and sharing `gh` auth files.
- The current agendum MCP/task API is read/create-heavy and does not yet expose all actions the GUI needs.
- Packaging Python plus dependencies inside a signed app needs explicit design.
- Finder-launched apps do not inherit shell `PATH`, so `gh` discovery cannot assume the terminal environment.
- SwiftPM development runs now prefer common Homebrew Python paths, but the production helper runner and bundled Python strategy are still unresolved.
- Current `gh auth login` flow is terminal-oriented and needs Mac-specific repair UX.
- SQLite ownership must stay behind the helper unless a later decision permits direct Swift DB access.

## Next actions
1. Watch PR #5 CI and address review feedback.
2. After PR #5 merges, continue with `workspace.list` / `workspace.select` or the first backend-backed `task.list` implementation.
3. Keep new backend command work covered by unit tests plus subprocess tests when process/environment behavior changes.

## After checkpoint
- Continue with `workspace.list` / `workspace.select` or backend-backed task loading.

## Drift from original plan
- Approved deviation: GUI work moved from `../agendum` into this standalone project.
- Approved deviation: public `main` is README-only; prototype work lives on stacked feature branches.
