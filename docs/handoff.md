# Handoff

## Current objective
Maintain the broad native macOS prototype baseline on `feature/mac-prototype`, with implementation checkpoints stacked above it.

## Branch
`feature/mac-prototype`

## Repo state
- HEAD: based on README-only `main`; run `git rev-parse --short HEAD` for the exact local commit.
- Remote: `origin` = `git@github.com:danseely/agendum-mac.git`
- Working tree: prototype baseline pending commit
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

## Validation
- `swift build` passes.
- Pending: `swift run AgendumMac`.

## Changed files
- `.gitignore`
- `Package.swift`
- `README.md`
- `Sources/AgendumMac/AgendumMacApp.swift`
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
1. Push `feature/mac-prototype`.
2. Rebase `feature/backend-helper` onto `feature/mac-prototype`.
3. Retarget PR #1 to `feature/mac-prototype`.

## Drift from original plan
- Approved deviation: GUI work moved from `../agendum` into this standalone project.
- Approved deviation: public `main` is README-only; prototype work lives on stacked feature branches.
