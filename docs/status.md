# Status

Last updated: 2026-04-28

## Current milestone
Mac prototype integration branch established.

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

## In progress
- Stack backend helper work on `feature/backend-helper` targeting `feature/mac-prototype`.

## Blocked
- None.

## Next
- Push `feature/mac-prototype`.
- Retarget `feature/backend-helper` onto `feature/mac-prototype`.
- Continue implementation through stacked feature branches.
