# Mac App Plan

## Active goal
Ship `agendum-mac` as a fully standalone native macOS app — Swift end-to-end, with its own backend engine and its own data store. No Python at runtime, no sibling-checkout dependency.

## Scope
- Single-language Swift app: SwiftUI surface + Swift engine + Swift data store.
- Own the GitHub transport layer (GraphQL via `URLSession`) and the auth flow (native OAuth Device Flow + Keychain).
- Own the SQLite database (GRDB v7+) under `~/Library/Application Support/Agendum/`.
- Architecture follows Apple's current canonical app shape (WWDC23 Observation, App/Scene/`@Observable`, `actor` for I/O, `@MainActor` for view state) and the layering Apple's sample apps use.

## Constraints
- Do not merge prototype implementation into `main` until explicitly requested.
- Keep public `main` README-only until the prototype is ready to become default-branch content.
- Use `feature/mac-prototype` as the broad integration branch.
- Do not push directly to `feature/mac-prototype`; update only through PRs from short-lived `codex/*` branches.
- Schema migrations go through `DatabaseMigrator`; ad-hoc schema mutations are forbidden once the GRDB store lands.
- Preserve the v0 helper protocol (`docs/backend-contract.md`) as the test asset throughout the Python-to-Swift migration; the helper façade dispatches to either Python or Swift internally during the migration.
- Avoid hand-authoring Xcode project internals; SwiftPM remains the primary build system.

## Non-goals
- No iCloud / multi-device sync at this scope.
- No `gh` CLI dependency in the shipping app (removed when issue B4 lands).
- No third-party persistence framework beyond GRDB (SwiftData / Core Data / Realm explicitly rejected for this codebase — see `docs/decisions.md` 2026-05-03 plan-revision entry).
- No TCA / Clean Architecture / VIPER / DI container adoption at current scope.

## Current epics
Replaced the prior five-item live-slice orchestration. See `docs/research/synthesis.md` for the cross-stream rationale and `docs/research/proposed-issues.md` for the drafted GitHub issue bodies (one per leaf below).

1. **Architecture modernization (Epic A).** Apple alignment: `@Observable` migration, `os.Logger`, `@SceneStorage`, AppKit-defaults relocation, module rename, polish.
2. **Standalone backend engine (Epic B).** Python → zero. Fork-and-vendor → port pure functions → port persistence/config/task-API → port GraphQL+auth → port sync planner → retire helper.
3. **Native data store (Epic C).** GRDB v7+: new `AgendumMacStore` target, `TaskStore` actor, dashboard reads, mutations, on-disk relocation.

## Phase order
Defined in `docs/research/synthesis.md`. Eight phases total; Phase 1 (mechanical foundations) is parallel-safe; Phase 6 is the long pole (sync planner + GraphQL transport); Phase 7 is the retirement (Python out, on-disk relocate); Phase 8 is polish (localization, deep links, accessibility, MetricKit).

## Canonical Supporting Docs
- `docs/status.md`: current milestone, done/in-progress/blocked/next state, and milestone exit criteria.
- `docs/decisions.md`: append-only decision log. Record plan changes here before silently changing direction.
- `docs/handoff.md`: current repo state, validation, changed files, and exact next actions.
- `docs/mac-gui-port-evaluation.md`: architectural assessment and open product/distribution risks (historical; superseded by the 2026-05-03 plan revision in `docs/decisions.md`).
- `docs/backend-contract.md`: v0 backend bridge contract; preserved as the test asset through the Python-to-Swift migration; deleted when the helper is retired (issue B6).
- `docs/testing.md`: testing strategy, milestone gates, and validation expectations.
- `docs/packaging.md`: distribution-channel matrix; seven picks deferred (the `~/.agendum` path policy is resolved by issue C5).
- `docs/research/`: 2026-05-03 architecture-direction research and proposed GitHub issue text.

## Milestones (historical)
The original five-milestone plan and the five-item live-slice orchestration are complete. See `docs/status.md` "Done" for the full record.

## Active milestone
"Standalone Swift app" arc, structured as the three epics (A / B / C) above and detailed in `docs/research/synthesis.md`. Phase 1 issues (A1, A2, B1) are the entry points.

## Testing Strategy
Testing grows with each migration slice. Through the Python-to-Swift port, both layers are tested side by side; once a slice ships, the Python tests for that surface either dispatch through the helper façade or are replaced by Swift tests covering the same cases.

- Pure-function ports (status derivation, attention classification, planner) are gated by parity tests: capture Python output for fixed inputs, port to Swift, assert byte-equal output.
- Data-layer ports use GRDB in-memory DBs for unit tests and `FakeTaskStore` for workflow tests.
- Workflow tests inject `AgendumBackendServicing` and `TaskStoreProviding` fakes; no real subprocess or network in unit tests.
- Real-subprocess JSONL integration tests stay green through the migration; deleted in Phase 7 with the helper.
- UI validation remains documented manual smoke tests for now.
- Each PR should update `docs/status.md` and `docs/handoff.md` with the exact validation commands and results.

The detailed testing plan lives in `docs/testing.md`.

## End-state Acceptance Criteria
At the end of the three epics:
- Repo contains zero Python (`Backend/` directory deleted).
- `swift build` produces a single shippable executable target.
- App opens its own SQLite store under `~/Library/Application Support/Agendum/` via GRDB.
- Sign-in works via native OAuth Device Flow on a clean machine with no `gh` installed.
- Sync, attention classification, manual create, and every per-task action match the Python implementation byte-for-byte against parity fixtures.
- All Apple-canonical hooks present: `@Observable` model, `os.Logger`, `@SceneStorage`, `Settings` scene, `.commands { ... }`, `UNUserNotificationCenter`, dock badge, `.onOpenURL`.
- Manual smoke and workflow tests pass with no helper subprocess running.

## Open Decision Gates
- Distribution channel (Direct / MAS / Homebrew cask / TestFlight).
- Code signing identity / notarization credentials.
- App icon / branding final asset.
- Crash reporting vendor selection beyond `MetricKit` baseline.
- Whether to adopt SQLiteData (GRDB + CloudKit) if multi-device sync ever becomes a goal.

## Out Of Scope (for now)
- Menu bar-only product shape.
- iCloud / multi-device sync.
- Touching `../agendum` (the engine fork lives in this repo from issue B1 onward).
