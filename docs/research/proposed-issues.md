# Proposed GitHub Issues

> Drafted 2026-05-03 from `docs/research/synthesis.md`. Each section below is a ready-to-paste issue body wrapped in a code fence so the raw markdown source is visible.
>
> **Filing status (2026-05-03):**
> - Epic A: filed as **#24** (https://github.com/danseely/agendum-mac/issues/24)
> - Epic B: filed as **#25** (https://github.com/danseely/agendum-mac/issues/25)
> - Epic C: filed as **#26** (https://github.com/danseely/agendum-mac/issues/26)
> - 17 leaf issues: not yet filed; per the user's instruction, leaves are filed as their phase approaches. The drafts below remain authoritative.
>
> When filing a leaf, replace its placeholder parent reference with the real epic number above. Per the user's global GitHub rule, posting any issue requires explicit approval.

## Suggested labels (create if missing)

- `epic`
- `area:architecture`
- `area:backend-engine`
- `area:data-store`
- `phase:1` … `phase:8`
- `breaking-change` (for the module rename, the on-disk relocation, the helper retirement)

---

## Epic A — Architecture modernization (Apple alignment)

**Title:** Epic: Architecture modernization (Apple alignment)
**Labels:** `epic`, `area:architecture`

```markdown
Track the architecture-modernization arc for `agendum-mac`. Brings the project into explicit alignment with Apple's current canonical app architecture (WWDC23 Observation, Apple's small-app sample shape, Backyard Birds-style module layering) and with industry SwiftUI best practices for an app of this size.

## Background
Drafted from `docs/research/architecture.md` and `docs/research/synthesis.md` after the 2026-05-03 architecture-direction research. Standing decisions to be added to `docs/decisions.md`:
- `@Observable` for new model objects; `ObservableObject` reserved for hosts that must support pre-macOS-14.
- Apple's three-question model decides property-wrapper choice; avoid `@StateObject`/`@ObservedObject`/`@EnvironmentObject` in new code.
- Cross-actor boundaries use `Sendable` value types; `@MainActor` on view-state classes is explicit; I/O lives on `actor`s.
- `os.Logger` per target under subsystem `com.danseely.agendum-mac`.
- Navigation restoration via `@SceneStorage`; deep links via `.onOpenURL`.
- Do not adopt TCA / Clean / VIPER / a generic DI container at current scope.

## Children
- [ ] A1 — Migrate `BackendStatusModel` to `@Observable` (#)
- [ ] A2 — `os.Logger` across all targets (#)
- [ ] A3 — `@SceneStorage` for selection / sidebar / filter state (#)
- [ ] A4 — Relocate AppKit/UN default seams to executable target (#)
- [ ] A5 — Module rename: `AgendumMacCore` → `AgendumBackend`; `AgendumMacWorkflow` → `AgendumFeature` (#)
- [ ] A6 — Polish bundle: localization, `.onOpenURL`, accessibility audit, `MetricKit` (#)

## Sequence
A1, A2 are Phase 1 (mechanical foundations, parallel-safe). A3, A4, A5 are Phase 2. A6 is Phase 8 polish.

## References
- `docs/research/architecture.md`
- `docs/research/synthesis.md`
```

---

### A1 — Migrate `BackendStatusModel` to `@Observable`

**Title:** A1: Migrate `BackendStatusModel` to `@Observable`; drop `ObservableObject`/`@Published`/`Combine`
**Labels:** `area:architecture`, `phase:1`

```markdown
## Why
Apple's canonical model-object pattern since WWDC23 ("Discover Observation in SwiftUI") is `@Observable`, not `ObservableObject` + `@Published` + Combine. Every 2024–2026 sample app uses it. Migration is mechanical, low-risk, and unlocks cleaner downstream changes (especially `@SceneStorage`, GRDB integration, and per-property change tracking).

## Scope
- `Sources/AgendumMacWorkflow/TaskWorkflowModel.swift`
  - Add `@Observable` to `BackendStatusModel`; drop `: ObservableObject` conformance.
  - Remove every `@Published` annotation; keep `private(set) var` access modifiers as-is.
  - Drop `import Combine` if it has no other consumers.
  - Verify `@MainActor` stays on the class (`@Observable` does NOT auto-isolate).
- `Sources/AgendumMac/AgendumMacApp.swift`
  - Replace `@StateObject private var model` → `@State private var model = BackendStatusModel(...)`.
  - Replace `@EnvironmentObject` with `@Environment(BackendStatusModel.self)`.
  - Replace `@ObservedObject` with plain stored properties; use `@Bindable var model` where bindings are needed.
- `Tests/AgendumMacWorkflowTests/`
  - Confirm tests still pass; nothing should depend on `objectWillChange`.
- `docs/decisions.md` entry: "`@Observable` is the default for new model objects."

## Out of scope
- Renaming the module (covered by A5).
- Splitting `BackendStatusModel` into smaller models.
- Touching `AgendumBackendClient` (the actor stays as-is).

## Dependencies
None. This is the foundation of the architecture epic.

## Acceptance criteria
- `BackendStatusModel` is `@Observable @MainActor public final class`.
- No `@Published` remains in `Sources/`.
- `AgendumMacApp.swift` uses `@State` / `@Environment(...)` / `@Bindable` only.
- All existing workflow tests pass unchanged.

## Validation gates
- `swift build` passes.
- `swift test --enable-code-coverage` passes; existing 119 Swift tests stay green.
- `/opt/homebrew/bin/python3 -m unittest discover -s Tests` passes (no Python touched).
- `swift run AgendumMac` smoke-launches without crash; observable refresh / filter / selection still drive view updates.
- `git diff --check` passes.

## References
- `docs/research/architecture.md` §1, §5
- WWDC23 Discover Observation in SwiftUI: https://developer.apple.com/videos/play/wwdc2023/10149/
- Apple migration guide: https://developer.apple.com/documentation/SwiftUI/Migrating-from-the-observable-object-protocol-to-the-observable-macro
```

---

### A2 — `os.Logger` across all targets

**Title:** A2: Adopt `os.Logger` with subsystem `com.danseely.agendum-mac`
**Labels:** `area:architecture`, `phase:1`

```markdown
## Why
There is no structured logging today. Errors are swallowed silently or surface only through `PresentedError`. `os.Logger` (unified logging) is Apple's recommended primitive: zero overhead when filtered out, redaction support, structured categories, surfaced in Console.app and `log stream`.

## Scope
- Add a `Logging.swift` (or per-target `log.swift`) declaring shared `Logger` instances:
  - `AgendumBackend` (was `AgendumMacCore`): `Logger(subsystem: "com.danseely.agendum-mac", category: "backend")`
  - `AgendumFeature` (was `AgendumMacWorkflow`): `category: "workflow"`
  - `AgendumMac` (executable): `category: "ui"`
- Replace silent `try?` swallows with `logger.error`; add `logger.notice` at top-level lifecycle events (refresh, workspace switch, sync-force start/end, task action, manual create, error mapping).
- Keep `PresentedError` user-facing surfaces unchanged; logging is additive.

## Out of scope
- Crash reporting (`MetricKit`) — covered by A6.
- Adding privacy redaction qualifiers beyond defaults; revisit in Phase 8.

## Dependencies
None. Strictly additive.

## Acceptance criteria
- Each target has at least one `Logger` instance scoped to its category.
- `Console.app` filtered by subsystem `com.danseely.agendum-mac` shows refresh / sync / task-action events during a smoke run.
- No `print(...)` calls remain in `Sources/`.

## Validation gates
- `swift build` passes.
- `swift test --enable-code-coverage` passes (test counts unchanged).
- `swift run AgendumMac` + `log stream --predicate 'subsystem == "com.danseely.agendum-mac"'` shows expected events.
- `git diff --check` passes.

## References
- `docs/research/architecture.md` §8
- SwiftLee — OSLog and Unified Logging: https://www.avanderlee.com/debugging/oslog-unified-logging/
```

---

### A3 — `@SceneStorage` for selection / sidebar / filter state

**Title:** A3: `@SceneStorage` for selection, sidebar visibility, and active filter
**Labels:** `area:architecture`, `phase:2`

```markdown
## Why
Mac users expect window state to survive relaunch. Apple's recommended primitive for per-scene restoration is `@SceneStorage`. Today the app loses selected task, sidebar visibility, and the active filter on every relaunch.

## Scope
- `Sources/AgendumMac/AgendumMacApp.swift`
  - Wrap `selectedTaskID: Int?` in `@SceneStorage("selectedTaskID")`.
  - Wrap `NavigationSplitView` `columnVisibility` in `@SceneStorage("sidebarVisibility")`.
  - Wrap the active filter source / status / project / includeSeen / limit in `@SceneStorage` (one key each, or a single Codable blob).
- Reconcile `BackendStatusModel.selectedTaskID` mirror with the scene-storage source of truth: scene storage owns it, model mirrors for command access.
- Add fake-backed workflow tests asserting that filter state round-trips through scene storage independently of the model's own state.

## Out of scope
- `.onOpenURL` deep links (A6).
- Window position / size restoration (Apple handles by default).

## Dependencies
- A1 (Observable) recommended first; not strictly required.

## Acceptance criteria
- Quitting and relaunching the app restores: last selected task, sidebar visibility, active filter.
- Multiple windows have independent restoration state (per-scene scope).
- Tests cover the model-side mirror behavior under filter changes.

## Validation gates
- `swift build` passes.
- `swift test --enable-code-coverage` passes; new workflow tests added.
- Manual smoke: launch, set filter+selection, quit, relaunch, observe restored state.
- `git diff --check` passes.

## References
- `docs/research/architecture.md` §6
- Nil Coalescing — State restoration with `SceneStorage`: https://nilcoalescing.com/blog/UsingSceneStorageForStateRestorationInSwiftUIApps/
```

---

### A4 — Relocate AppKit/UN default seams to executable target

**Title:** A4: Move `defaultURLOpener` / `defaultPasteboard` / `defaultNotifier` / `defaultBadgeSetter` into `AgendumMac`
**Labels:** `area:architecture`, `phase:2`

```markdown
## Why
The feature target (`AgendumMacWorkflow`) currently imports `AppKit` and `UserNotifications` only to provide *default implementations* of platform-specific seams. The protocol typealiases (`URLOpening`, `Pasteboarding`, `Notifying`, `BadgeSetting`) are pure `@Sendable` closures; the defaults are AppKit-flavored. Moving the defaults out makes the feature target AppKit-free, faster to compile and test, and matches Apple sample apps that keep platform glue in the app target.

## Scope
- Move `defaultURLOpener`, `defaultPasteboard`, `defaultNotifier`, `defaultBadgeSetter` from `Sources/AgendumMacWorkflow/TaskWorkflowModel.swift` to a new `Sources/AgendumMac/PlatformSeams.swift` (or `Defaults.swift`).
- Remove `import AppKit` / `import UserNotifications` (or `@preconcurrency import UserNotifications`) from the feature target.
- Update `AgendumMacApp.swift` to inject these defaults at `BackendStatusModel.init(...)`.
- Update tests that previously relied on the in-target default to inject explicit fakes.

## Out of scope
- Module rename (A5).
- Adding new platform seams (e.g. file dialogs).

## Dependencies
- A1 (Observable) recommended; not required.
- Resolves a design tension; ideally lands before A5 so the rename touches less code.

## Acceptance criteria
- `Sources/AgendumMacWorkflow/` has no `AppKit` or `UserNotifications` imports.
- All seam defaults live in the executable target.
- Workflow tests still pass; no test imports `AppKit`.

## Validation gates
- `swift build` passes.
- `swift test --enable-code-coverage` passes; test counts unchanged or grow.
- `swift run AgendumMac` smoke launches; URL open + notifications + dock badge still work.
- `git diff --check` passes.

## References
- `docs/research/architecture.md` §3
```

---

### A5 — Module rename

**Title:** A5: Rename modules — `AgendumMacCore` → `AgendumBackend`; `AgendumMacWorkflow` → `AgendumFeature`
**Labels:** `area:architecture`, `phase:2`, `breaking-change`

```markdown
## Why
"Mac" is implicit in this repo (no other platform target). The current module names duplicate it. Apple sample apps use shorter data/UI names (`BackyardBirdsData`, `BackyardBirdsUI`); industry conventions use `Feature` for view-state targets. The rename improves grep-ability and makes the data-store and backend-engine epics easier to read in PR diffs.

## Scope
- `Package.swift`: rename targets, libraries, and test targets.
- Rename source directories: `Sources/AgendumMacCore/` → `Sources/AgendumBackend/`; `Sources/AgendumMacWorkflow/` → `Sources/AgendumFeature/`.
- Rename test directories and target names.
- Find/replace `AgendumMacCore` → `AgendumBackend` and `AgendumMacWorkflow` → `AgendumFeature` across `Sources/`, `Tests/`, `docs/`, `Scripts/`, CI workflow.
- Update all `import` statements.

## Out of scope
- Splitting the targets further (deferred until there's a second feature surface).
- Renaming `BackendStatusModel`, `AgendumBackendClient`, `TaskItem`, etc. — types stay.

## Dependencies
- A4 should land first so the rename diff is smaller.

## Acceptance criteria
- New module names compile and link.
- All imports updated.
- All planning docs (`docs/plan.md`, `docs/handoff.md`, `docs/status.md`, `docs/decisions.md`, `docs/testing.md`, `docs/packaging.md`, `docs/research/*.md`) refer to the new names.
- CI workflow YAML references the new names.

## Validation gates
- `swift build` passes.
- `swift test --enable-code-coverage` passes (counts unchanged).
- `swift run AgendumMac` smoke launches.
- `grep -r AgendumMacCore Sources Tests docs Scripts .github` returns nothing.
- `grep -r AgendumMacWorkflow Sources Tests docs Scripts .github` returns nothing.
- `git diff --check` passes.

## References
- `docs/research/architecture.md` §3
- Apple Backyard Birds layering: https://github.com/apple/sample-backyard-birds
```

---

### A6 — Polish bundle (localization, deep links, accessibility, MetricKit)

**Title:** A6: Polish bundle — localization, `.onOpenURL`, accessibility, MetricKit
**Labels:** `area:architecture`, `phase:8`

```markdown
## Why
Table-stakes Mac polish that's missing today. Each is a real user-facing gap; together they make the app feel finished. Defer to Phase 8 because none of them block the standalone-engine or data-store work.

## Scope (each can split into its own sub-issue if it grows)
- **Localization**: introduce `Localizable.xcstrings`; replace inline string literals with `String(localized: "...")`; verify pluralization on count strings ("3 tasks").
- **Deep links**: add a documented URL scheme; handle `.onOpenURL { route(url) }` on the root scene; route to specific task or workspace.
- **Accessibility audit**: VoiceOver pass on dashboard / detail / Settings / sheet; `.accessibilityLabel`, `.accessibilityValue`, `.accessibilityHint` where missing; `.dynamicTypeSize(...)` honored.
- **MetricKit**: subscribe `MXMetricManager` to capture diagnostic payloads (CPU, hangs, crashes); log via `os.Logger` (or feed Sentry/Crashlytics if a vendor is later picked).

## Out of scope
- Localization for a second locale (can ship English-first; once xcstrings is in place adding a locale is a translation pass).
- Crash-reporting vendor selection (Sentry/Crashlytics) — separate decision once `MetricKit` baseline is in.

## Dependencies
- A1, A2, A3, A4, A5 all helpful but not required.
- All other epics ideally landed first so polish doesn't interleave with structural change.

## Acceptance criteria
- `Localizable.xcstrings` exists with every user-facing string covered.
- App responds to `agendum://...` URLs (or chosen scheme) routing to a task / workspace.
- Accessibility Inspector reports zero issues on the main flows.
- `MetricKit` payloads are captured to log on launch.

## Validation gates
- `swift build`, `swift test`, `swift run` smoke unchanged.
- Manual VoiceOver pass on golden paths.
- Manual deep-link smoke from Terminal: `open "agendum://..."`.
- `git diff --check` passes.

## References
- `docs/research/architecture.md` §8
```

---

## Epic B — Standalone backend engine (Python → zero)

**Title:** Epic: Standalone backend engine (Python → zero)
**Labels:** `epic`, `area:backend-engine`

```markdown
Track the Python-to-Swift backend-engine migration. End state: zero Python in the shipping `agendum-mac` runtime; all engine logic — workspace/config, GitHub GraphQL transport + auth, sync planner, attention classification, manual task creation, status transitions — owned by Swift code in this repo.

## Background
Drafted from `docs/research/backend-engine.md` and `docs/research/synthesis.md` after the 2026-05-03 architecture-direction research. The Python engine (~3,300 LOC, source of truth in `../agendum/src/agendum/`) gets vendored into this repo first, then ported module-by-module to Swift behind the unchanged v0 helper protocol. The helper subprocess is deleted last.

The single biggest behavior-drift risk is the sync planner port (B5). Plan parity tests *before* code lands.

## Children (in dependency order)
- [ ] B1 — Fork-and-vendor Python engine into `Backend/agendum_engine/` (#)
- [ ] B2 — Port pure status-derivation functions to Swift (#)
- [ ] B3 — Port `db.py` / `config.py` / `task_api.py` equivalents to Swift (#)
- [ ] B4 — Port GitHub GraphQL transport + replace `gh` with native OAuth Device Flow (#)
- [ ] B5 — Port `syncer.py` planner to Swift with parity tests (#)
- [ ] B6 — Retire Python helper subprocess; remove Python from runtime (#)

## Standing decisions
- v0 helper protocol (`docs/backend-contract.md`) is the test asset; preserve it through every B-issue. The helper façade dispatches to either Python or Swift internally during the migration.
- GitHub auth becomes native OAuth Device Flow + Keychain (no `gh` CLI) as part of B4.
- Native GitHub client uses `URLSession` for both REST and GraphQL; no third-party SDK by default. (Octokit.swift is an option; default to hand-rolled.)

## References
- `docs/research/backend-engine.md`
- `docs/research/synthesis.md`
- `docs/backend-contract.md`
```

---

### B1 — Fork-and-vendor Python engine

**Title:** B1: Fork-and-vendor `agendum` engine into `Backend/agendum_engine/`
**Labels:** `area:backend-engine`, `phase:1`, `breaking-change`

```markdown
## Why
The user's stated coupling pain: `agendum-mac` requires a sibling checkout of `../agendum`. Forking the engine into this repo eliminates that requirement in a single PR with zero behavior change. It is also the prerequisite for every subsequent Swift-port slice (B2 through B6).

After this lands, `../agendum` is no longer load-bearing; `agendum-mac` owns the engine going forward.

## Scope
- Copy `../agendum/src/agendum/` to `agendum-mac/Backend/agendum_engine/`. Prefer `git subtree add` to preserve commit history; flat copy is acceptable if subtree is too disruptive.
- Update `Backend/agendum_backend/helper.py` `_bootstrap_agendum_import()` (lines 24–31) to import the in-tree copy unconditionally.
- Update `Tests/test_backend_helper.py` and `Tests/test_backend_helper_process.py` import paths.
- Update `Scripts/python_coverage.py` to point at the in-tree copy.
- Update `.github/workflows/test.yml` to drop the sibling-`agendum` checkout step.
- Add a `Backend/agendum_engine/LICENSE` and `Backend/agendum_engine/README.md` documenting:
  - Origin commit SHA from `../agendum` at fork point.
  - Divergence policy: this is no longer kept in sync with upstream; the Mac app evolves it independently.
  - Any upstream license attribution.
- New `docs/decisions.md` entry: "Forked the `agendum` engine into `Backend/agendum_engine/`. Sibling-checkout discipline retired. Engine evolution now happens here."

## Out of scope
- Any Swift port of any engine module (B2–B5).
- Runtime / packaging changes (still `swift run AgendumMac` + Python helper).
- Removing the existing `Backend/agendum_backend_helper.py` shim.

## Dependencies
None. Can land in parallel with A1 / A2.

## Acceptance criteria
- `Backend/agendum_engine/` exists with the engine source.
- `swift run AgendumMac` and all Python tests work without `../agendum` present on disk.
- CI checks out only `agendum-mac`.
- Decision-log entry recorded.

## Validation gates
- `swift build` passes.
- `swift test --enable-code-coverage` passes (counts unchanged).
- `/opt/homebrew/bin/python3 -m unittest discover -s Tests` passes (61 tests).
- `/opt/homebrew/bin/python3 Scripts/python_coverage.py` passes; coverage stays ≥ 91%.
- Temporarily move `../agendum` aside and confirm `swift run AgendumMac` and tests still pass.
- `git diff --check` passes.

## References
- `docs/research/backend-engine.md` §3, §6
- `docs/research/synthesis.md` Phase 1
```

---

### B2 — Port pure status-derivation functions to Swift

**Title:** B2: Port `gh.py` pure status-derivation functions to Swift
**Labels:** `area:backend-engine`, `phase:4`

```markdown
## Why
The status-derivation functions in `gh.py` lines 40–202 (`derive_authored_pr_status`, `derive_review_pr_status`, `derive_issue_status`, `has_unacknowledged_review_feedback`) are pure: input → output, no I/O, no global state, no GraphQL. They have existing Python tests and are the easiest, highest-confidence first port. They also exercise the "helper façade dispatches to Swift" pattern that every later B-issue depends on.

## Scope
- New file in `AgendumBackend` (or a sibling target — pick one and document): pure Swift implementations of the four derivation functions.
- Port the existing Python test fixtures to Swift tests; results must match Python output byte-for-byte across all fixture cases.
- Modify `Backend/agendum_engine/gh.py` so these four functions delegate to the Swift implementations (via the helper boundary or a temporary FFI; pick the lowest-friction approach).
- v0 helper protocol unchanged.

## Out of scope
- GraphQL transport (B4).
- Sync planner (B5).
- Touching auth / `gh` (B4).

## Dependencies
- B1 (vendored engine).
- A1, A2, A5 helpful but not required.

## Acceptance criteria
- Four Swift functions match Python output on the entire ported fixture set.
- `task.list` results unchanged from before the port (any task whose status depends on these functions resolves identically).
- Swift test count grows; Python tests for the same functions stay green via dispatch.

## Validation gates
- `swift build` passes.
- `swift test --enable-code-coverage` passes; new tests added.
- `/opt/homebrew/bin/python3 -m unittest discover -s Tests` passes.
- `swift run AgendumMac` smoke launches; Issues / Manual lists render with correct status badges.
- `git diff --check` passes.

## References
- `docs/research/backend-engine.md` §1 (status-derivation as the trivial-port category)
- Python source: `Backend/agendum_engine/gh.py` lines 40–202 (after B1)
```

---

### B3 — Port `db.py` / `config.py` / `task_api.py` to Swift

**Title:** B3: Port persistence + config + task-API to Swift
**Labels:** `area:backend-engine`, `phase:5`

```markdown
## Why
Once status derivation (B2) is Swift-side, the next trivial-port targets are `db.py` (197 LOC), `config.py` (213 LOC), and `task_api.py` (175 LOC). Together they cover SQLite CRUD, workspace path resolution, TOML config loading, namespace normalization, manual task creation, and the eight task-action commands. After B3, every helper task.* command can run end-to-end in Swift.

This issue interlocks with the C-epic: `db.py`'s SQLite role is replaced by `TaskStore` (C2). Implement this issue *after* C2 lands so the data layer has one Swift source of truth.

## Scope
- Port `db.py` schema definitions and CRUD into `TaskStore` (already from C2). Add any C2-missing operations: `add_task`, `update_task`, `find_task_by_gh_url`, `find_tasks_by_gh_node_ids`, `mark_all_seen`.
- Port `config.py` `RuntimePaths`, namespace regex, default-config writer with 0o700/0o600 perms; landing in `AgendumBackend` (or a new `AgendumConfig` target, decide at design time).
- Port `task_api.py` manual task creation, status transition, mark-seen, remove. Helper façade dispatches to these Swift functions.
- Maintain on-disk format parity: existing `~/.agendum/agendum.db` and config files continue to work.

## Out of scope
- GitHub GraphQL transport / auth (B4).
- Sync planner (B5).
- On-disk relocation (C5).

## Dependencies
- B1, B2.
- C1, C2 (data store target + TaskStore actor).
- A1 (Observable model interaction).

## Acceptance criteria
- All 8 helper task.* commands route through Swift code.
- `task.createManual`, `task.markSeen`, `task.markReviewed`, `task.markInProgress`, `task.moveToBacklog`, `task.markDone`, `task.remove` produce identical SQLite mutations to the Python implementations on a fixture DB.
- Workspace selection, namespace handling, and config defaults match Python behavior.
- Python tests for these commands either pass (dispatching) or are replaced by Swift tests with the same coverage.

## Validation gates
- `swift build` passes.
- `swift test --enable-code-coverage` passes; significant Swift test growth.
- `/opt/homebrew/bin/python3 -m unittest discover -s Tests` passes (or the test set has been migrated).
- `swift run AgendumMac` smoke: workspace switch, manual create, every task action.
- `git diff --check` passes.

## References
- `docs/research/backend-engine.md` §1
- `docs/research/data-store.md` §6 (smallest first slice)
```

---

### B4 — Port GraphQL transport + replace `gh` with native OAuth

**Title:** B4: Port GitHub transport to Swift; replace `gh` with native OAuth Device Flow + Keychain
**Labels:** `area:backend-engine`, `phase:6`, `breaking-change`

```markdown
## Why
`gh.py` is 1,546 LOC, with the GraphQL query authoring, paging, completeness tracking, and `gh` CLI subprocess invocation all entangled. Porting this is the biggest functional slice in the engine migration. It also forces resolving the long-standing `gh` dependency: the user-installed `gh` CLI is incompatible with sandboxing/MAS, and replacing it with a native OAuth Device Flow + Keychain token store is required for any MAS-eligible distribution.

This is the second-highest-risk slice in the arc (after B5). Approach it with parity fixtures from real GitHub responses, captured before the port and asserted byte-equal in Swift.

## Scope
- New `AgendumGitHub` target (or extend `AgendumBackend` — design at start): Swift `URLSession`-based GraphQL client with the same query builders, paging behavior (`_HYDRATE_BATCH_SIZE=50`, `_VERIFY_BATCH_SIZE=50`, repo chunk 10), and completeness tracking (`(items, ok)` tuple equivalent) the Python has.
- Native OAuth Device Flow client (use AppAuth-iOS or hand-rolled — choose at start; record decision). Token stored in Keychain (`SecItemAdd` / `SecItemCopyMatching`).
- New helper command surface (or replacement on the existing `auth.*` commands) for: start-device-flow, poll-device-flow, sign-out, current-token-status.
- SwiftUI Settings updates: replace the "install gh / gh auth login" repair UX with a "Sign in with GitHub" device-flow UI.
- Helper façade routes `auth.*` and any GraphQL-needing commands to Swift; Python `gh.py` stops being called from the helper.
- Fixture suite: capture real GitHub responses for representative authored-PR / assigned-issue / review-requested-PR / repo-archive / hydration / verification scenarios. Assert Swift transport reproduces the same `(items, ok)` outputs.

## Out of scope
- Sync planner (B5).
- Removing Python entirely (B6).
- Notifications-API REST port can land here or be split into its own slice — decide at design time.

## Dependencies
- B1, B2, B3.

## Acceptance criteria
- `gh` CLI is no longer invoked anywhere in the runtime path.
- `auth.diagnose` / `auth.status` payloads are produced from Swift state.
- Sign-in flow works end-to-end on a clean machine (no `gh`, no existing token).
- Captured fixtures replay byte-equal across Python and Swift.

## Validation gates
- `swift build` passes.
- `swift test --enable-code-coverage` passes; transport fixture suite added.
- `/opt/homebrew/bin/python3 -m unittest discover -s Tests` passes for any remaining Python (likely just `syncer.py`-adjacent tests at this point).
- `swift run AgendumMac` smoke: complete sign-in on a token-less machine; refresh; force sync.
- `git diff --check` passes.

## References
- `docs/research/backend-engine.md` §1, §5
- AppAuth-iOS: https://github.com/openid/AppAuth-iOS
- Native macOS OAuth pattern docs (to gather at design time)
```

---

### B5 — Port `syncer.py` planner to Swift

**Title:** B5: Port sync planner to Swift with parity tests
**Labels:** `area:backend-engine`, `phase:6`, `risk:high`

```markdown
## Why
`syncer.py` (1,056 LOC) is the single largest behavior-risk in the entire arc. The state machine — `OpenDiscoveryCoverage` → `OpenHydrationBundle` → `MissingVerificationRequest` → `MissingVerificationBundle` → `CloseSuppression` → `SyncPlan` → `diff_tasks` → `_apply_sync_diff` → `_apply_notifications` — encodes per-lane close suppression, repo-archive filtering, scoped-org backfill, `pr_review` exemption from `fetched_repos`, and the entire attention-classification surface. None of this has a formal spec. The product's value lives here.

The acceptable risk strategy is parity tests: capture real Python sync runs against fixed GitHub fixtures, port the planner to Swift, drive the Swift planner against the same fixtures, assert byte-equal output (`SyncPlan`, `diff_tasks`, `_apply_*` results).

## Scope
- New `SyncPlanner` (target placement TBD at design): Swift port of the entire `syncer.py` state machine.
- Parity-fixture harness: a recorded set of (GitHub-response-snapshot, prior-DB-state, expected-SyncPlan, expected-diff, expected-final-DB-state) tuples. Generated from Python first; Swift planner asserted against the same tuples.
- Helper façade routes `sync.force` / `sync.status` to the Swift planner.
- All attention-classification rules covered by named test cases: `review_received`, `re-review requested`, `changes requested`, `approved`, notification-driven re-unseen, close-suppression on partial fetch, scoped-org backfill, `pr_review` exemption.

## Out of scope
- Removing Python from runtime (B6).
- `~/Library/Application Support` relocation (C5).
- Optimization passes — first port targets functional parity, not performance gains.

## Dependencies
- B1, B2, B3, B4 all required.
- C1, C2, C3, C4 required (Swift owns the data layer the planner mutates).

## Acceptance criteria
- Every fixture in the parity harness produces byte-equal output between Python and Swift.
- `sync.force` end-to-end: real GitHub → Swift transport (B4) → Swift planner → `TaskStore` (C2) writes → SwiftUI updates.
- Existing badge / attention indicators still drive correctly off Swift planner output.

## Validation gates
- `swift build` passes.
- `swift test --enable-code-coverage` passes; parity harness > 50 fixtures.
- `swift run AgendumMac` smoke: full sync against the user's real account produces the same task list / attention badge as Python.
- `git diff --check` passes.

## References
- `docs/research/backend-engine.md` §1 (the sync planner section, including `_task_is_verifiable_in_planner_scope` lines 738–749)
- Python source: `Backend/agendum_engine/syncer.py` (after B1)
```

---

### B6 — Retire Python helper subprocess

**Title:** B6: Retire Python helper subprocess; remove Python from runtime
**Labels:** `area:backend-engine`, `phase:7`, `breaking-change`

```markdown
## Why
End state of the standalone-engine arc. Once B2–B5 have moved every engine surface to Swift and C-epic has moved persistence to Swift, the helper subprocess is dead weight. Deleting it removes the last Python dependency from the runtime, drops ~700 LOC of helper glue, and unblocks the packaging-decision matrix in `docs/packaging.md` (no more "Python helper runtime" question to answer).

## Scope
- Delete `Backend/agendum_backend/`, `Backend/agendum_backend_helper.py`, and `Backend/agendum_engine/` (the engine has been ported; the source-of-truth is now in Swift).
- Replace `AgendumBackendClient` (the JSONL-over-stdio actor) with a thin Swift-in-Swift facade over the new in-process services (`TaskStore`, `SyncPlanner`, `GitHubClient`, `AuthClient`). v0 contract preserved as a Swift API surface so the SwiftUI surface area never changes.
- Delete `Tests/test_backend_helper.py` and `Tests/test_backend_helper_process.py`.
- Delete `Scripts/python_coverage.py` and the Python coverage CI step.
- Delete sibling-checkout discipline references throughout `docs/`.
- New `docs/decisions.md` entry: "Python removed from runtime. `agendum-mac` is single-language Swift."

## Out of scope
- On-disk relocation (C5) — separate concern, can land before or after.
- Polish (A6).

## Dependencies
- B1, B2, B3, B4, B5 all required.
- C1, C2, C3, C4 required.

## Acceptance criteria
- No Python files anywhere in the repo.
- `Package.swift` + Swift sources build and run the entire app end-to-end.
- CI runs only Swift jobs (no Python toolchain required).
- App size and startup are no worse than the helper-based version.

## Validation gates
- `swift build` passes.
- `swift test --enable-code-coverage` passes.
- `swift run AgendumMac` — full smoke (refresh / workspace / filter / detail / actions / sign-in / sync) — no behavior change.
- CI runs without any Python step and stays green.
- `git diff --check` passes.

## References
- `docs/research/backend-engine.md` §6
- `docs/research/synthesis.md` Phase 7
```

---

## Epic C — Native data store (GRDB)

**Title:** Epic: Native data store (GRDB)
**Labels:** `epic`, `area:data-store`

```markdown
Track the data-store migration. End state: `agendum-mac` owns its own SQLite database via GRDB.swift v7+, stored under `~/Library/Application Support/Agendum/`, with the existing schema preserved one-to-one. The 2026-04-28 "helper owns SQLite" decision is reversed.

## Background
Drafted from `docs/research/data-store.md` and `docs/research/synthesis.md` after the 2026-05-03 architecture-direction research. GRDB chosen over SwiftData (sharp edges + forces schema rewrite), Core Data (stylistically out of step with Swift 6), and others (EOL / weaker SwiftUI fit / wrong shape).

## Children
- [ ] C1 — Add `AgendumMacStore` SwiftPM target on GRDB v7+ (#)
- [ ] C2 — `TaskStore` actor + `TaskStoreProviding` protocol seam (#)
- [ ] C3 — Wire dashboard reads through `TaskStoreProviding` (#)
- [ ] C4 — Wire mutations through `TaskStore` (#)
- [ ] C5 — Relocate on-disk store to `~/Library/Application Support/Agendum/` (#)

## Standing decisions
- Persistence: GRDB v7+. SwiftData / Core Data / Realm not adopted.
- Schema management: all migrations through `DatabaseMigrator`. No ad-hoc schema mutations.
- Concurrency: `DatabaseQueue` (single-writer serialized) initially; upgrade to `DatabasePool` only if read contention surfaces.

## References
- `docs/research/data-store.md`
- `docs/research/synthesis.md`
```

---

### C1 — Add `AgendumMacStore` target on GRDB

**Title:** C1: Add `AgendumMacStore` SwiftPM target on GRDB v7+; `TaskRecord` 1:1 with current schema
**Labels:** `area:data-store`, `phase:3`

```markdown
## Why
Foundation slice for the data-store epic. Stand up a SwiftPM target with GRDB, define a `TaskRecord` Swift type that mirrors the Python `tasks` table 1:1, and wire `DatabaseMigrator` so future schema changes have a controlled path.

This issue does NOT change runtime behavior — nothing reads from the store yet. It makes subsequent issues smaller.

## Scope
- New SwiftPM target `AgendumMacStore` (placement: a sibling library target alongside `AgendumBackend` and `AgendumFeature`).
- Add GRDB.swift v7+ as a package dependency.
- `TaskRecord: Codable, FetchableRecord, PersistableRecord` mirroring the 16 columns of the existing `tasks` table.
- `DatabaseSchema` wrapper exposing `DatabaseMigrator` registration; v1 = "current Python schema" (no-op when opening an existing DB; full schema create when opening a fresh DB).
- New file `AgendumMacStore/Schema.swift` documenting the schema for future migrations.

## Out of scope
- `TaskStore` actor (C2).
- Wiring to `BackendStatusModel` (C3).
- On-disk relocation (C5).

## Dependencies
- A1 helpful (cleaner integration with `@Observable`); not required.

## Acceptance criteria
- `swift build` includes `AgendumMacStore`.
- Tests for `TaskRecord` round-trip via in-memory DB pass.
- Opening an existing `~/.agendum/agendum.db` file returns the expected schema with no migration error.

## Validation gates
- `swift build` passes.
- `swift test --enable-code-coverage` passes; new `AgendumMacStoreTests` added.
- `swift run AgendumMac` smoke unchanged (no runtime use yet).
- `git diff --check` passes.

## References
- `docs/research/data-store.md` §1, §6
- GRDB.swift: https://github.com/groue/GRDB.swift
- Existing schema: `Backend/agendum_engine/db.py` (after B1) lines 8–28
```

---

### C2 — `TaskStore` actor + `TaskStoreProviding` protocol seam

**Title:** C2: `TaskStore` actor + `TaskStoreProviding` protocol seam in feature target
**Labels:** `area:data-store`, `phase:3`

```markdown
## Why
Define the boundary the rest of the C-epic builds against. `TaskStore` is the actor-isolated Swift API for reads and writes; `TaskStoreProviding` is the test seam mirroring the existing `AgendumBackendServicing` pattern.

## Scope
- `AgendumMacStore.TaskStore` actor:
  - `init(path: URL)`
  - `func tasks(matching: TaskListFilters) async throws -> [TaskItem]`
  - `func observe(matching: TaskListFilters) -> AsyncStream<[TaskItem]>` (uses `ValueObservation.values(in:)`).
  - `func task(id: TaskItem.ID) async throws -> TaskItem?`
  - `func markSeen(id: TaskItem.ID) async throws`
  - (more action methods land in C4)
- Mapping layer: `TaskRecord` ↔ `TaskItem` (existing value type from `AgendumFeature`).
- `protocol TaskStoreProviding` in `AgendumFeature` mirroring the actor's API.
- `FakeTaskStore` for tests, parallel to `FakeBackend`.

## Out of scope
- Wiring `BackendStatusModel` (C3).
- Mutations beyond `markSeen` placeholder (C4).

## Dependencies
- C1.
- A1 recommended.

## Acceptance criteria
- `TaskStore` reads + observes + `markSeen` work against an in-memory DB in tests.
- `FakeTaskStore` exists with deterministic behavior; usable in `AgendumFeatureTests` (or whatever the renamed target is).

## Validation gates
- `swift build` passes.
- `swift test --enable-code-coverage` passes; new tests for `TaskStore` and `FakeTaskStore`.
- `git diff --check` passes.

## References
- `docs/research/data-store.md` §3, §6
- Existing seam pattern: `AgendumFeature.AgendumBackendServicing`
```

---

### C3 — Wire dashboard reads through `TaskStoreProviding`

**Title:** C3: Wire dashboard reads through `TaskStoreProviding`
**Labels:** `area:data-store`, `phase:4`

```markdown
## Why
First user-visible win: the SwiftUI dashboard reads tasks from the GRDB-backed `TaskStore` instead of from the helper subprocess. Round-trip latency drops from "stdio JSONL exchange per request" to "in-process SQLite query." Filter changes feel instant.

The Python helper continues to *produce* tasks via sync (writes to the same SQLite file under WAL); the Mac app stops using the helper for *reads*.

## Scope
- `BackendStatusModel.refresh()` and `loadTaskItems(...)` route to `TaskStoreProviding.tasks(matching:)`.
- `BackendStatusModel.observe...` consumes `TaskStoreProviding.observe(matching:)` `AsyncStream` and republishes to `tasks`.
- `BackendStatusModel.task(id:)` (used by detail pane) routes to the store.
- The helper's `task.list` and `task.get` commands stay in place for safety; they become unused on the read path but are not deleted yet.
- Concurrent-writer note: while the helper is still the sync producer, both Python and Swift open the same SQLite file. WAL handles concurrency. Document this in a `Backend/agendum_engine/CONCURRENCY.md` (or similar) with the constraint that mutations from Swift happen only during sync-idle windows. C4 narrows that window further.

## Out of scope
- Mutations through the store (C4).
- Replacing the helper as the sync producer (B-epic).
- On-disk relocation (C5).

## Dependencies
- C1, C2.
- A1 strongly recommended.

## Acceptance criteria
- Dashboard task list, filter changes, detail pane all driven by `TaskStore` on the read path.
- No `task.list` or `task.get` calls in helper logs during a smoke run.
- Workflow tests inject `FakeTaskStore` and pass.

## Validation gates
- `swift build` passes.
- `swift test --enable-code-coverage` passes; workflow test counts grow.
- `swift run AgendumMac` smoke: launch, switch workspace, filter, select task, open detail. All driven from store. Force-sync still works (helper produces; UI sees changes via `ValueObservation`).
- `git diff --check` passes.

## References
- `docs/research/data-store.md` §3, §6
- `docs/research/synthesis.md` Phase 4
```

---

### C4 — Wire mutations through `TaskStore`

**Title:** C4: Route task mutations (markSeen / status / manual create / remove) through `TaskStore`
**Labels:** `area:data-store`, `phase:5`

```markdown
## Why
Closes the "Swift owns the data path" loop on the UI side. Every task mutation the user can trigger from the dashboard or detail pane lands in the GRDB-backed `TaskStore` rather than going to the helper.

Lands after B3 (Swift port of `task_api`) so there's a single Swift implementation of each mutation rather than two.

## Scope
- `TaskStore` adds: `markReviewed`, `markInProgress`, `moveToBacklog`, `markDone`, `remove`, `createManual` mutation APIs.
- `BackendStatusModel.performTaskAction(taskID:_:)`, `createManualTask(...)`, `removeTask(...)` route to `TaskStore`.
- Helper's `task.*` commands either become Swift-backed (via dispatch) or are deleted if the helper façade is already routing through Swift.
- All workflow tests use `FakeTaskStore` for mutations.

## Out of scope
- Sync producer changes (B-epic / B5).
- On-disk relocation (C5).

## Dependencies
- C1, C2, C3.
- B3 (Swift `task_api` equivalents).

## Acceptance criteria
- All task mutations on dashboard/detail land via `TaskStore`.
- No task.* helper command is called during a smoke run.
- Per-task error surfacing remains intact.

## Validation gates
- `swift build` passes.
- `swift test --enable-code-coverage` passes.
- `swift run AgendumMac` smoke: every per-task action + manual create + remove. Errors still scoped per-task.
- `git diff --check` passes.

## References
- `docs/research/data-store.md` §3, §4
- `docs/research/synthesis.md` Phase 5
```

---

### C5 — Relocate store to `~/Library/Application Support/Agendum/`

**Title:** C5: Relocate on-disk store to `~/Library/Application Support/Agendum/`; one-shot import from legacy `~/.agendum/`
**Labels:** `area:data-store`, `phase:7`, `breaking-change`

```markdown
## Why
Sandbox-friendly location, matching Apple HIG. `~/.agendum` is a holdover from the TUI's Unix-style hidden directory; sandboxed Mac apps cannot use it reliably. Moving the store unblocks any future MAS / sandbox / tightened-entitlements packaging slice.

Lands in Phase 7 (after B6 retires the Python helper) because the legacy `~/.agendum` location must keep working for the duration of the migration to support concurrent Python helper writes.

## Scope
- `TaskStore` defaults to `~/Library/Application Support/Agendum/agendum.sqlite`.
- One-shot importer on first launch:
  - If `~/Library/Application Support/Agendum/` does not exist and `~/.agendum/` does, copy the SQLite + config.
  - Leave `~/.agendum/` untouched (so the user can still run an older agendum-mac if they have one). Display a "Migrated from ~/.agendum/" notice in Settings on first run.
- Config-file relocation: any TOML configs follow the same path.
- Settings UI surfaces the new path; "Show in Finder" button optional.
- New `docs/decisions.md` entry: "On-disk store moved to ~/Library/Application Support/Agendum/. Sandbox-friendly. One-shot legacy import implemented."

## Out of scope
- Sandbox entitlements (separate packaging decision).
- Removing legacy `~/.agendum/` files (we don't delete user data on migration).

## Dependencies
- C1, C2, C3, C4.
- B6 strongly recommended (Python helper out, so no concurrent-writer constraint).

## Acceptance criteria
- Fresh install creates `~/Library/Application Support/Agendum/`.
- Existing `~/.agendum/agendum.db` is imported once on first run after this lands.
- Settings shows the active store path.

## Validation gates
- `swift build` passes.
- `swift test --enable-code-coverage` passes; importer covered by tests.
- `swift run AgendumMac` smoke against a clean home, an existing `~/.agendum/` home, and an existing `~/Library/Application Support/Agendum/` home.
- `git diff --check` passes.

## References
- `docs/research/data-store.md` §4, §6
- `docs/research/synthesis.md` Phase 7
- `docs/packaging.md` deferred decision #7 (`~/.agendum` path policy) — this issue resolves it.
```

---

## Posting checklist

Before any of these get filed:

1. Confirm with the user that the epic structure and ordering are right.
2. Confirm label set above (`epic`, `area:*`, `phase:*`, `breaking-change`).
3. File the three epic issues first; capture their numbers.
4. File the seventeen work issues with `#NN` placeholders replaced by real epic numbers.
5. Add each work issue's number to its epic's checkbox list.
6. Open a tracking PR for the planning docs (this directory + `docs/plan.md` + `docs/decisions.md` + `docs/status.md` + `docs/handoff.md` updates) so the issue text and the in-repo plan are version-controlled together.
