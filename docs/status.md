# Status

Last updated: 2026-04-30

## Current milestone
Swift helper-process wiring checkpoint is ready to merge through PR #5.

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

## In progress
- Merging PR #5 into `feature/mac-prototype`, then starting the next short-lived branch.

## Blocked
- None.

## Next
- Keep CI aligned with local validation as new test layers are added.
- Keep `main` README-only until the prototype is ready.
- Use short-lived branches and PRs for all changes targeting `feature/mac-prototype`.
- After PR #5 lands, continue with `workspace.list` / `workspace.select` or the first backend-backed task list command on a new short-lived branch.
- Keep `feature/mac-prototype` as the broad integration branch.
