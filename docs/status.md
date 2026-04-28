# Status

Last updated: 2026-04-28

## Current milestone
Ready for the next backend/UI implementation checkpoint.

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

## In progress
- Choosing between Swift helper-process wiring and `workspace.list` / `workspace.select`.

## Blocked
- None.

## Next
- Keep CI aligned with local validation as new test layers are added.
- Keep `main` README-only until the prototype is ready.
- Continue with Swift helper-process wiring or `workspace.list` / `workspace.select`.
- Keep `feature/mac-prototype` as the broad integration branch.
