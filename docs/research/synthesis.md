# Architecture Direction Synthesis

> Written 2026-05-03 to capture cross-stream conclusions from the three research reports in this directory. Companion docs: `docs/research/backend-engine.md` (Stream A), `docs/research/data-store.md` (Stream B), `docs/research/architecture.md` (Stream C). The proposed GitHub issues live in `docs/research/proposed-issues.md`.

## What changed

The user has chosen a stronger direction than any single research stream proposed:

1. **`agendum-mac` is a fully standalone product.** No sibling-checkout dependency on `../agendum`. Engine evolution happens in this repo from now on.
2. **All Python is removed from the runtime.** Not "Python forever," not "Briefcase-bundled Python." Zero Python in the shipping app.
3. **The Mac app owns its own data store.** The 2026-04-28 "helper owns SQLite" decision is reversed.
4. **Architecture follows Apple's current canonical guidance and industry best practices.** Specifically: `@Observable`, `@MainActor`/`actor` concurrency split, MV (not MVVM, not TCA, not VIPER), the same module layering Apple's sample apps use.

This contradicts three current `docs/plan.md` non-goals — see the plan-revision entry being added to `docs/decisions.md` for the explicit list.

## Cross-stream picks

| Decision | Pick | Rationale |
|---|---|---|
| Backend engine end state | **All Swift, native** | User directive. Stream A's recommended sequence (fork-and-vendor → incremental Swift port) becomes the path *to* that end state, not the end state itself. |
| Data store | **GRDB.swift v7+** | Maps existing schema 1:1, no rewrite, full Swift 6 / Sendable, `ValueObservation` integrates cleanly with `@Observable`. SwiftData rejected: schema rewrite forced, multiple documented sharp edges (CloudKit-link bug on macOS Release builds, migration crashes, ordering bugs, ~2× memory). |
| Architecture pattern | **MV with `@Observable`** | Apple's canonical small-app shape since WWDC23. TCA over-spec for a single-window dashboard with one model and one I/O dependency. |
| Module shape | **Keep three-target split, rename** | Mirrors Apple Backyard Birds: data target / UI target / app target. `AgendumMacCore` → `AgendumBackend`; `AgendumMacWorkflow` → `AgendumFeature`. |
| GitHub auth | **Native OAuth Device Flow + Keychain** | Replaces user-installed `gh`. Required for sandbox/MAS eligibility; lands as part of the GraphQL-transport port. |
| Concurrency | **Keep current `actor` + `@MainActor` split** | Already textbook Swift 6 SwiftUI shape. |
| Testing seam | **Keep `…Servicing` protocol pattern** | Add `TaskStoreProviding` alongside `AgendumBackendServicing`. Defer `swift-dependencies` / `@Dependency` until there are 3+ services. |
| On-disk location | **Move to `~/Library/Application Support/Agendum/`** | Sandbox-friendly. One-shot import from legacy `~/.agendum/` for users coming from the TUI. |

## Sequencing

Eight phases, with every leaf scoped to fit the same per-PR rhythm as the five-item live-slice orchestration we just shipped. Phase numbers reflect ordering constraints; items inside a phase can run in parallel or in any order.

### Phase 1 — Mechanical foundations (parallel)
- **A1** Migrate `BackendStatusModel` to `@Observable`; drop `ObservableObject`/`@Published`/`Combine`.
- **A2** Introduce `os.Logger` with subsystem `com.danseely.agendum-mac` and per-target categories.
- **B1** Fork-and-vendor Python engine into `Backend/agendum_engine/`; drop sibling-checkout from CI.

### Phase 2 — Modernization completion
- **A3** `@SceneStorage` for selection / sidebar visibility / filter state.
- **A4** Relocate AppKit/UN default seams (`URLOpener`, `Pasteboard`, `Notifier`, `BadgeSetter`) to the executable target.
- **A5** Module rename: `AgendumMacCore` → `AgendumBackend`, `AgendumMacWorkflow` → `AgendumFeature`.

### Phase 3 — Data store foundation
- **C1** Add `AgendumMacStore` SwiftPM target on GRDB v7; `TaskRecord` 1:1 with current schema; `DatabaseMigrator` set up.
- **C2** `TaskStore` actor + `TaskStoreProviding` protocol seam in feature target; `FakeTaskStore` for tests.

### Phase 4 — Early Swift slices (parallel)
- **C3** Wire dashboard reads through `TaskStoreProviding`. Helper continues to produce sync (writes to the same SQLite file under WAL).
- **B2** Port pure status-derivation functions (`gh.py` lines 40–202) to Swift behind unchanged v0 helper boundary; helper now dispatches to either Python or Swift for these calls.

### Phase 5 — Data layer Swift-side
- **B3** Port `db.py` / `config.py` / `task_api.py` equivalents to Swift. Helper task-action commands now route through Swift code.
- **C4** Wire all mutations (markSeen, status transitions, manual create, remove) through the store. Helper task.* commands shrink or disappear.

### Phase 6 — The hard ones
- **B4** Port GitHub GraphQL transport to Swift (`URLSession` + GraphQL); replace `gh` with native OAuth Device Flow + Keychain token storage. Helper auth.* commands become thin wrappers over Swift.
- **B5** Port sync planner (`syncer.py`, ~1,056 LOC) to Swift. This is the highest-risk slice — close-suppression rules, attention classification, and per-lane partial-fetch behavior have no formal spec and must be ported with parity tests.

### Phase 7 — Retirement
- **B6** Retire Python helper subprocess. `Backend/` directory deleted. CI no longer runs Python tests. `BackendClient` actor talks to in-process Swift services.
- **C5** Move on-disk store to `~/Library/Application Support/Agendum/`. One-shot import from legacy `~/.agendum/`. Sandbox-friendly.

### Phase 8 — Polish
- **A6** Localization scaffold (`Localizable.xcstrings`), accessibility audit, `.onOpenURL` deep-link, `MetricKit` crash/hang reporting.

## Standing architectural decisions

These should be added to `docs/decisions.md` as durable constraints all subsequent code follows:

- `@Observable` is the default for new model objects. `ObservableObject` reserved for hosts that must support pre-macOS-14.
- Apple's three-question model decides property-wrapper choice (`@State` / `@Environment` / `@Bindable`). Avoid `@StateObject` / `@ObservedObject` / `@EnvironmentObject` in new code.
- Cross-actor boundaries use `Sendable` value types; `@MainActor` on view-state classes is explicit; I/O lives on `actor`s.
- Each target gets its own `os.Logger` category under subsystem `com.danseely.agendum-mac`.
- Test seams are protocol-typed, live in the feature target, and have hand-rolled fakes.
- Navigation state for restoration uses `@SceneStorage`. Deep links arrive through `.onOpenURL`.
- Adopt `swift-testing` for new test files; do not migrate XCTest suites until they need rework anyway.
- Persistence layer: GRDB v7+. SwiftData / Core Data not adopted at this scope.
- GitHub auth: native OAuth Device Flow + Keychain. `gh` CLI dependency removed once Phase 6 lands.
- Do not adopt TCA, Clean Architecture, VIPER, or a generic DI container at current scope. Revisit if the app grows past three feature surfaces.

## Risks called out

- **Sync planner port (B5)** is the single biggest behavior-drift risk in the entire arc. The Python `syncer.py` rules are encoded as imperative code with no formal spec; close-suppression and attention classification are exactly the behaviors that make the product useful. Mitigation: snapshot the Python output for a recorded GitHub state, port to Swift, drive the Swift implementation against the same snapshot, and assert byte-equal task lists. Plan for parity tests *before* code lands.
- **GRDB schema-migration discipline.** Once Swift owns the schema, all migrations go through `DatabaseMigrator`. Ad-hoc schema mutations are forbidden. This needs to become a review-gate the first time C-epic touches the schema.
- **Phase-4 concurrent SQLite writers.** During Phase 4 the Python helper (sync producer) and the Swift store (UI mutations) both write to the same SQLite file. WAL handles concurrency, but write-write conflicts on the same row are still possible. Either route Phase-4 mutations through the helper temporarily, or accept that mutations only happen during sync-idle windows. Decide before C4 ships.
- **Phase 6 is the long pole.** Realistically multi-week. Keep the v0 helper protocol intact during the port so the SwiftUI surface area never breaks; the helper just shrinks until B6 deletes it.

## What this doesn't decide

- **Distribution channel.** The seven still-deferred packaging picks in `docs/packaging.md` remain deferred. This direction makes Direct + notarytool *and* MAS reachable; the choice between them is still the user's. Phase 8 is a reasonable place to revisit.
- **iCloud / multi-device sync.** Out of scope. SQLiteData (built on GRDB) is the migration target if this ever becomes a goal.
- **Crash reporting vendor.** `MetricKit` is the Apple-recommended baseline; whether to also add Sentry/Crashlytics is a Phase 8 decision.
- **`Agendum.app` icon and branding.** Already partially answered (2026-05-02 decision); the placeholder will need replacing before any user-facing release.

## Pointer to issues

Drafted GitHub issue text — one issue per leaf in the phase plan above, ready to paste — lives in `docs/research/proposed-issues.md`. Per the user's global rule on GitHub interactions, those are drafts only and require explicit approval before posting.
