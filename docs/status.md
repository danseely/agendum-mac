# Status

Last updated: 2026-04-28

## Current milestone
Backend helper implementation started.

## Milestone exit criteria
- `docs/backend-contract.md` exists and covers task loading, task actions, sync, namespace, auth, error schema, and protocol versioning. Done.
- Bridge choice is recorded in `docs/decisions.md`. Done.
- Next implementation step is precise enough for a fresh session to start without re-planning. Done.

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

## In progress
- Backend helper v0 implementation review on stacked PR #1.

## Blocked
- None.

## Next
- Continue implementation through stacked feature branches.
- Keep `main` README-only until the prototype is ready.
- Continue with Swift helper-process wiring or `workspace.list` / `workspace.select`.
- Keep `feature/mac-prototype` as the broad integration branch.
