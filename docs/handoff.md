# Handoff

## Current objective
Implement the first backend-helper checkpoint as a stacked branch above `feature/mac-prototype`.

## Branch
`feature/backend-helper`

## Repo state
- HEAD: based on `feature/mac-prototype`; run `git rev-parse --short HEAD` for the exact local commit.
- Remote: `origin` = `git@github.com:danseely/agendum-mac.git`
- PR: `https://github.com/danseely/agendum-mac/pull/1`, targeting `feature/mac-prototype`
- Parent PR: `https://github.com/danseely/agendum-mac/pull/2`, draft, targeting `main`
- Working tree: clean after this handoff update is committed
- Last validation date: 2026-04-28

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

## Validation
- `swift build` passes.
- `python3 -m unittest discover -s Tests` passes.
- Smoke-tested JSONL helper invocation with `workspace.current` and `auth.status`.
- Pending: `swift run AgendumMac`.

## Changed files
- `.gitignore`
- `Backend/agendum_backend/__init__.py`
- `Backend/agendum_backend/helper.py`
- `Backend/agendum_backend_helper.py`
- `Package.swift`
- `README.md`
- `Sources/AgendumMac/AgendumMacApp.swift`
- `Tests/test_backend_helper.py`
- `docs/plan.md`
- `docs/status.md`
- `docs/decisions.md`
- `docs/handoff.md`
- `docs/mac-gui-port-evaluation.md`
- `docs/backend-contract.md`

## Risks / blockers
- A Mac App Store build is likely harder if the app depends on launching external `gh` and sharing `gh` auth files.
- The current agendum MCP/task API is read/create-heavy and does not yet expose all actions the GUI needs.
- Packaging Python plus dependencies inside a signed app needs explicit design.
- Finder-launched apps do not inherit shell `PATH`, so `gh` discovery cannot assume the terminal environment.
- Current `gh auth login` flow is terminal-oriented and needs Mac-specific repair UX.
- SQLite ownership must stay behind the helper unless a later decision permits direct Swift DB access.

## Next actions
1. Review backend helper checkpoint on stacked PR #1.
2. Continue with Swift helper-process wiring or `workspace.list` / `workspace.select`.
3. Update planning docs after the next implementation checkpoint.

## Drift from original plan
- Approved deviation: GUI work moved from `../agendum` into this standalone project.
- Approved deviation: public `main` is README-only; prototype work lives on stacked feature branches.
