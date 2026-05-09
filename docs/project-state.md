# Project State

## Goal
Ship `agendum-mac` as a fully standalone native macOS app: Swift end-to-end, with its own backend engine and SQLite data store. End state: no Python at runtime, no sibling-checkout dependency, native GitHub auth, GRDB-backed persistence, and Apple-canonical app architecture.

## Constraints / Non-goals
- Keep public `main` README-only until the prototype is ready to become default-branch content.
- Use `feature/mac-prototype` as the integration branch.
- Do not push directly to `feature/mac-prototype`; use short-lived `codex/*` branches and PRs targeting `feature/mac-prototype`.
- Do not merge PRs unless explicitly asked.
- Preserve the v0 helper protocol in `docs/backend-contract.md` as the test asset through the Python-to-Swift migration.
- Schema migrations must go through `DatabaseMigrator` once the GRDB store lands.
- SwiftPM remains the primary build system; avoid hand-authoring Xcode project internals.
- No iCloud / multi-device sync at this scope.
- No `gh` CLI dependency in the shipping app after issue B4 lands.
- No third-party persistence framework beyond GRDB.
- Do not adopt TCA, Clean Architecture, VIPER, or a generic DI container at current scope.

## Links
- Parent PR: #2 `feature/mac-prototype` -> `main` (draft).
- Architecture epic: #24.
- Backend engine epic: #25.
- Native data store epic: #26.
- Draft leaf issue bodies: `docs/research/proposed-issues.md`.
- Backend contract: `docs/backend-contract.md`.
- Testing strategy: `docs/testing.md`.
- Legacy split planning files: `docs/plan.md`, `docs/status.md`, `docs/decisions.md`, `docs/handoff.md` (historical/reference only; current operational state lives here).

## Current State
- Branch: `feature/mac-prototype`.
- Integration branch: `feature/mac-prototype` is aligned with `origin/feature/mac-prototype`; C1 code landed as `c9cebde` and the post-C1 handoff refresh landed as `63a0efa`.
- Open PRs: draft parent PR #2 only.
- Open epics: #24, #25, #26.
- Done: A1 (#27), A2 (#29), B1 (#31), B2 (#33), A4 (#35), A5 (#37), A3 (#40), visual list/dashboard realignment (#42), and C1 native store schema foundation (#44) are merged into `feature/mac-prototype`.
- In progress: native data store epic #26 remains active; C2 is the next C-epic leaf.
- Blocked: no implementation-level blocker.
- Next checkpoint: file/start C2 when ready, using the residual notes below.

## Decisions
- 2026-04-28: Decision: create separate local `agendum-mac` project. Reason: avoid churning the existing terminal CLI repo. Impact: GUI planning and app scaffold live here. Plan change: yes.
- 2026-04-28: Decision: use JSON-over-stdio helper process for the first live prototype. Reason: isolate Swift/Python and own a narrow contract. Impact: `docs/backend-contract.md` became the bridge contract. Plan change: yes.
- 2026-04-28: Decision: use stacked branches. Reason: keep README-only `main` minimal while reviewing prototype work. Impact: `feature/mac-prototype` is the integration branch; leaf branches target it. Plan change: yes.
- 2026-04-28: Decision: add explicit testing gates and CI. Reason: helper boundary, workspace/auth, sync lifecycle, and Swift integration are high-risk. Impact: local validation and GitHub Actions are part of every checkpoint. Plan change: yes.
- 2026-05-02: Decision: add `AgendumMacWorkflow` target and `AgendumBackendServicing` seam. Reason: keep backend protocol models separate from app workflow state and make fake-backed workflow tests possible. Impact: executable imports workflow target; tests fake backend behavior. Plan change: no.
- 2026-05-03: Decision: revise plan to standalone Swift app. Reason: Python packaging/signing cost is structurally hostile to shipping; GRDB and modern Swift architecture fit the end state better. Impact: Python is now planned for removal; data store and backend engine move into Swift. Plan change: yes.
- 2026-05-03: Decision: `@Observable` is the default for new model objects. Reason: Apple-canonical macOS 14+ app shape. Impact: A1 migrated `BackendStatusModel`. Plan change: no.
- 2026-05-03: Decision: adopt `os.Logger` per target under subsystem `com.danseely.agendum-mac`. Reason: structured diagnostics and Apple alignment. Impact: A2 landed logging categories. Plan change: no.
- 2026-05-04: Decision: vendor the Python engine in-tree under `Backend/agendum_engine/`. Reason: remove sibling-checkout dependency before Swift port slices. Impact: B1 retired the sibling checkout. Plan change: no.
- 2026-05-05: Decision: B2 shadow-ports pure GitHub status derivation to Swift before runtime dispatch. Reason: parity for pure functions without temporary Python-to-Swift bridge mechanics. Impact: shared parity fixtures now lock the behavior. Plan change: yes; runtime dispatch deferred.
- 2026-05-07: Decision: adopt the current `planning-handoff` skill state model. Reason: the skill now makes `docs/project-state.md` and `docs/features.json` canonical. Impact: active state is consolidated here; old split planning files remain legacy references. Plan change: yes for planning artifacts only.
- 2026-05-07: Decision: A5 stale-reference validation is strict only for executable/build surfaces. Reason: research and legacy docs intentionally preserve old module-name history and mapping context. Impact: `rg -n "AgendumMacCore|AgendumMacWorkflow" Package.swift Sources Tests Scripts .github` is the zero-match gate; docs are audited separately for intentional historical mappings/legacy references. Plan change: yes for validation guidance.
- 2026-05-07: Decision: A5 landed as a pure module rename without type renames. Reason: keep the rename mechanical and avoid behavior churn before A3/C/B work. Impact: SwiftPM targets are now `AgendumBackend` and `AgendumFeature`; type names such as `BackendStatusModel`, `AgendumBackendClient`, and `TaskItem` stay unchanged. Plan change: no.
- 2026-05-07: Decision: A3 dashboard workflow model ownership moved from `AgendumMacApp` app scope into `DashboardSceneRoot` scene scope. Reason: per-window `@SceneStorage` restoration must not share one `BackendStatusModel` across windows. Impact: each `WindowGroup` scene has its own `BackendStatusModel.live()`, selection, source selection, split-view visibility, and active filters; Settings uses a separate app/settings model. Plan change: yes for A3 architecture.
- 2026-05-07: Decision: A3 menu commands route through a focused scene value instead of app-global state. Reason: menu actions must target the active window and avoid a "last changed window wins" shared mirror. Impact: command availability and task actions read the focused scene's model and selected-task binding. Plan change: yes for A3 architecture.
- 2026-05-07: Decision: keep `@SceneStorage` bridges in `AgendumMac` and expose only plain restoration helpers in `AgendumFeature`. Reason: workflow model tests should stay SwiftUI-free while first refresh still uses restored filters. Impact: `BackendStatusModel.restoreSceneState(filters:selectedTaskID:)` seeds plain model state before `refresh()`. Plan change: no.
- 2026-05-08: Decision: realign the Mac dashboard around the terminal app's sectioned triage list. Reason: the previous sidebar/detail-pane design drifted from the desired single-list workflow. Impact: `All` is the default source, issues and manual tasks are separate sections, task actions move to a focused sheet, and status/section colors mirror `../agendum/src/agendum/widgets.py`. Plan change: yes for visual/layout direction.
- 2026-05-08: Decision: publish C1 after adversarial review loop and merge when green. Reason: user explicitly requested that all follow-up findings be captured, the handoff docs updated, and the C1 PR merged after checks pass. Impact: C1 leaf issue #44 was completed by PR #45, merged into `feature/mac-prototype` as `c9cebde`. Plan change: no.

## Drift
- Approved deviation: GUI work moved from `../agendum` into this standalone project.
- Approved deviation: public `main` is README-only; prototype work lives on stacked feature branches.
- Approved deviation: 2026-05-03 plan revision replaces the earlier Python-helper shell framing with standalone Swift app / Python removal.
- Approved deviation: B2 was pulled forward immediately after B1 by user direction, ahead of its nominal phase order; runtime dispatch was explicitly deferred.
- 2026-05-07 drift check: no new unapproved drift. A5 remains the named Phase 2 checkpoint, A4 landed first as required, and no active PR supersedes A5.
- 2026-05-07 review drift fix: `docs/features.json` had marked A5 passed before PR #38 landed, and legacy `docs/handoff.md` still carried stale live-sounding branch/checkpoint guidance. Resolution: A5 is `in_progress` until merge or explicit acceptance; `docs/handoff.md` now points to this canonical state instead of carrying operational instructions.
- 2026-05-07 post-merge drift check: no new unapproved drift. A5 landed after explicit user approval to merge PR #38; A3 remains the next architecture checkpoint.
- 2026-05-07 A3 drift check: approved deviation from the original A3 draft: do not use an app-scoped dashboard model. Revised A3 scope requires per-scene models and focused command routing; implementation follows that reviewed design.
- 2026-05-08 visual/layout drift check: approved correction. The product direction now prioritizes the terminal app's dense sectioned triage list over the earlier Mac detail-pane layout, while retaining native sidebar, toolbar, sheets, menus, and state restoration.
- 2026-05-08 C1 drift check: no unapproved drift. C1 is the next critical-path leaf because B3 explicitly depends on C1/C2 and A6 is Phase 8 polish. Leaf issue #44 was filed after explicit user approval to publish.

## Validation
- Last full checkpoint validation: A4 / PR #36 on 2026-05-06: `swift build`; `swift test --enable-code-coverage` (118 XCTest tests plus 7 Swift Testing cases); `/opt/homebrew/bin/python3 -m unittest discover -s Tests` (68 tests); `/opt/homebrew/bin/python3 Scripts/python_coverage.py` (499/540 lines, 92.4%); `Scripts/build_app_bundle.sh`; bundle existence/executable checks; `plutil -lint`; `swift run AgendumMac` launch smoke; `git diff --check`; platform-reference grep for `AgendumMacWorkflow`.
- Current docs review-fix validation: docs-only change; `jq . docs/features.json`, `git diff --check`, and focused `rg` spot checks passed. Full Swift/Python suite was not rerun; prior A5 local validation and PR #38 GitHub Actions `Test` were already passing.
- A5 local validation passed: `swift build`; `swift test --enable-code-coverage` (118 XCTest tests plus 7 Swift Testing cases); `/opt/homebrew/bin/python3 -m unittest discover -s Tests` (68 tests); `/opt/homebrew/bin/python3 Scripts/python_coverage.py` (499/540 lines, 92.4%); `swift run AgendumMac` smoke launch stayed running until terminated; strict build-surface stale grep returned no matches; active docs audit found old names only in intentional mappings/historical legacy docs; `jq . docs/features.json`; `git diff --check`.
- A5 PR #38 GitHub Actions `Test` check passed on 2026-05-07 and PR #38 merged into `feature/mac-prototype` as squash commit `6f6d388`.
- A5 issue #37 was closed as completed after PR #38 merged.
- A3 local validation on branch `codex/a3-scene-storage` / PR #41: `swift build` passed; `swift test --enable-code-coverage` passed (121 XCTest tests plus 7 Swift Testing tests); `/opt/homebrew/bin/python3 -m unittest discover -s Tests` passed (68 tests); `/opt/homebrew/bin/python3 Scripts/python_coverage.py` passed (499/540 lines, 92.4%); `swift run AgendumMac` startup smoke stayed running until terminated with `kill`.
- A3 PR #41 GitHub Actions `Test` check passed on 2026-05-07.
- A3 manual bundle smoke on 2026-05-08 found two bugs: sidebar source rows were not selectable and filters did not persist across launch. Fix: tag sidebar rows explicitly and write filter/source/selection state through scene storage plus UserDefaults fallback for fresh default-window launches. Retest confirmed sidebar selection and filter/source/page-size persistence across launches. Residual: split-view column width changes do not persist; treat as layout polish outside A3 state-restoration scope unless visual redesign requires it.
- A3 follow-up adversarial review found the fallback could overwrite an intentionally default restored scene. Fix: added a scene-local `dashboard.didInitializeState` sentinel so the UserDefaults fallback only applies to fresh default-window launches, not restored scene sessions.
- A3 PR #41 merged into `feature/mac-prototype` on 2026-05-08 as squash commit `0650976`; issue #40 closed as completed.
- Visual list local validation on branch `codex/visual-layout-direction` / issue #42 / PR #43: `swift build`; `swift build --target AgendumMac`; `swift test --filter AgendumFeatureTests.TaskWorkflowModelTests` (111 XCTest tests before review fix); `swift test --enable-code-coverage` (126 XCTest tests plus 7 Swift Testing tests before review fix); `/opt/homebrew/bin/python3 -m unittest discover -s Tests` (68 tests); `/opt/homebrew/bin/python3 Scripts/python_coverage.py` (499/540 lines, 92.4%); `Scripts/build_app_bundle.sh`; bundle existence/executable checks; `plutil -lint .build/Agendum.app/Contents/Info.plist`; `swift run AgendumMac` launch smoke stayed running until terminated with `kill`; `jq . docs/features.json`; `git diff --check`.
- Visual list PR #43 review-fix validation: stale hidden-task selection/action targeting fixed by revalidating visible selection and resolving action tasks only from visible sections; `swift build --target AgendumMac`; `swift test --filter TaskWorkflowModelTests/testTaskDisplaySectionsTaskLookupOnlySearchesVisibleSections`; `swift test --enable-code-coverage` (127 XCTest tests plus 7 Swift Testing tests); `git diff --check`.
- Visual list PR #43 adversarial F1 validation: repo display fallback was real; fixed `TaskItem.project` fallback to `project -> ghRepo -> "No project"` so rows/modals show GitHub repo when project is nil; `swift test --filter TaskWorkflowModelTests` (114 XCTest tests); `swift build --target AgendumMac`; `git diff --check`.
- Visual list PR #43 merged into `feature/mac-prototype` on 2026-05-08 as squash commit `d516b86`; GitHub Actions `Test` passed on the merge head; issue #42 closed as completed.
- Post-visual handoff refresh landed on `feature/mac-prototype` as `a6b679c`.
- C1 local validation on branch `codex/c1-grdb-store-schema`: `swift build` passed and resolved GRDB.swift `7.10.0`; `swift test --filter AgendumMacStoreTests` passed (3 Swift Testing tests); `swift test --enable-code-coverage` passed (129 XCTest tests plus 10 Swift Testing tests); `swift run AgendumMac` built and launch-smoked until terminated with `kill`; `git diff --check` passed.
- C1 adversarial review found a real legacy migration gap: existing DBs without `gh_node_id` would fail when creating `idx_tasks_gh_node_id`. Fix: `DatabaseSchema` now ensures `gh_node_id` before index creation; store tests now cover the missing-column migration path plus column metadata, partial indexes, and `gh_url` uniqueness. Post-fix validation: `swift test --filter AgendumMacStoreTests` passed (5 Swift Testing tests); `swift test --enable-code-coverage` passed (129 XCTest tests plus 12 Swift Testing tests). Review also found stale C1 draft issue wording; fixed in `docs/research/proposed-issues.md`.
- C1 second/third/fourth adversarial reviews found `TaskRecord` could allow Swift insert paths to encode `NULL` timestamps, unlike Python `add_task`, which always writes `last_changed_at`, `created_at`, and `updated_at`. Fix: the public initializer now requires non-optional timestamp values, timestamp fields are not externally settable, and custom GRDB persistence encoding throws rather than writing `NULL` when a legacy-read record has nil required timestamps. Post-fix validation: `swift test --filter AgendumMacStoreTests` passed (7 Swift Testing tests); `swift test --enable-code-coverage` passed (129 XCTest tests plus 14 Swift Testing tests).
- C1 fifth adversarial review found `seen` was nullable in SQLite but non-optional in `TaskRecord`, and `active` status cleanup was migration-only rather than repeatable like Python `init_db`. Fix: `TaskRecord.seen` is nullable, `DatabaseSchema.prepare(_:)` runs migrations plus repeatable legacy status cleanup, and tests cover nullable `seen` reads plus post-migration `active` cleanup. Post-fix validation: `swift test --filter AgendumMacStoreTests` passed (9 Swift Testing tests); `swift test --enable-code-coverage` passed (129 XCTest tests plus 16 Swift Testing tests).
- C1 sixth adversarial review found no findings. Residuals for C2: store-opening code should use `DatabaseSchema.prepare(_:)`; mapping tests should cover nullable `seen` and legacy nullable timestamps when converting records to app-facing tasks. Publication residual: include `Package.resolved` with the PR.
- C1 final pre-publication validation on branch `codex/c1-grdb-store-schema`: `swift build` passed; `swift test --enable-code-coverage` passed (129 XCTest tests plus 16 Swift Testing tests); `swift run AgendumMac` built and launch-smoked until terminated with `kill`; `jq . docs/features.json` passed; `git diff --check` passed. No `agent-check` script exists in this repo.
- C1 PR #45 GitHub Actions `Test` check passed on 2026-05-09; PR #45 merged into `feature/mac-prototype` as squash commit `c9cebde`; issue #44 closed as completed.
- `python3` in the user shell may resolve to pyenv 3.10.2, which lacks `tomllib`; use `/opt/homebrew/bin/python3` for local helper validation.

## C1 Work Packet
- Objective: add the native GRDB store foundation without changing runtime dashboard behavior.
- Parent: native data store epic #26.
- Leaf issue: #44, filed from `docs/research/proposed-issues.md` section "C1 - Add `AgendumMacStore` target on GRDB".
- Branch: `codex/c1-grdb-store-schema`, based on `feature/mac-prototype` at `a6b679c`.
- PR: #45.
- Status: complete; PR #45 merged as `c9cebde`, and issue #44 is closed.
- Implementation scope:
  - Add SwiftPM product/target `AgendumMacStore`.
  - Add GRDB.swift dependency, currently resolved to `7.10.0` in `Package.resolved`; include `Package.resolved` when committing/publishing this slice.
  - Add `DatabaseSchema.migrator()` with the current Python `tasks` schema and indexes.
  - Add `DatabaseSchema.prepare(_:)` for migration plus repeatable Python-compatible legacy status cleanup.
  - Add `TaskRecord` mirroring the current task table columns; public construction and custom persistence encoding prevent new Swift writes with nil required timestamps.
  - Add in-memory migration/round-trip tests in `AgendumMacStoreTests`, including older DBs missing `gh_node_id`.
- Out of scope:
  - `TaskStore` actor and `TaskStoreProviding` seam (C2).
  - Dashboard reads through store (C3).
  - Mutations through store (C4).
  - Application Support relocation/import (C5).
- Follow-up notes:
  - C2 should open databases through `DatabaseSchema.prepare(_:)`, not only `DatabaseSchema.migrator().migrate(...)`.
  - C2 record-to-domain mapping tests should cover nullable `seen` and legacy nullable timestamp rows.
- Validation gates:
  - `swift build`
  - `swift test --filter AgendumMacStoreTests`
  - `swift test --enable-code-coverage`
  - `swift run AgendumMac` smoke launch
  - `git diff --check`

## A5 Work Packet
- Objective: rename modules from `AgendumMacCore` to `AgendumBackend` and from `AgendumMacWorkflow` to `AgendumFeature`.
- Parent: architecture epic #24.
- Leaf issue: #37.
- PR: #38.
- Source of issue body: `docs/research/proposed-issues.md` section "A5 - Module rename".
- Labels: `area:architecture`, `phase:2`, `breaking-change` if they exist.
- Branch: create `codex/a5-module-rename` from current `feature/mac-prototype`; target PR back to `feature/mac-prototype`.
- PR body: include `relates to #<A5 issue number>`.
- Status: complete; PR #38 merged as `6f6d388`, issue #37 closed.
- Implementation scope:
  - Rename `Package.swift` products, targets, test targets, and dependencies.
  - Rename directories: `Sources/AgendumMacCore/` -> `Sources/AgendumBackend/`; `Sources/AgendumMacWorkflow/` -> `Sources/AgendumFeature/`; `Tests/AgendumMacCoreTests/` -> `Tests/AgendumBackendTests/`; `Tests/AgendumMacWorkflowTests/` -> `Tests/AgendumFeatureTests/`.
  - Update Swift imports and `@testable import` lines.
  - Update fixture paths, especially `Tests/test_gh_status_derivation.py`.
  - Update docs, scripts, CI workflow references, and any package/test target names.
  - Keep type names unchanged: `BackendStatusModel`, `AgendumBackendClient`, `TaskItem`, and existing protocol/type surfaces stay as-is.
- Suggested implementation order:
  1. File the A5 issue with `gh issue create --body-file <tmpfile>`. Done: #37.
  2. Create `codex/a5-module-rename`. Done.
  3. Move directories first, then update `Package.swift`, then imports and references. Done.
  4. Run the stale-reference grep before tests to catch mechanical misses. Done for build surfaces.
  5. Run the validation gates below and open the PR. Done: PR #38.
- Validation gates:
  - `swift build`
  - `swift test --enable-code-coverage`
  - `/opt/homebrew/bin/python3 -m unittest discover -s Tests`
  - `/opt/homebrew/bin/python3 Scripts/python_coverage.py`
  - `swift run AgendumMac` smoke launch
  - `rg -n "AgendumMacCore|AgendumMacWorkflow" Package.swift Sources Tests Scripts .github` returns no matches.
  - Active docs audit: old names may appear only as intentional historical mappings or legacy references; old split docs are not current operational guidance.
  - `git diff --check`
- Main risk: stale old module references in tests, fixture paths, CI, or planning docs. Avoid unrelated type renames.

## Handoff / Next Actions
1. Start C2 when ready; use `DatabaseSchema.prepare(_:)` for store opening and cover nullable `seen` / legacy nullable timestamps in mapping tests.
2. Keep PR #2 as the parent durable context; do not merge it until explicitly requested.
