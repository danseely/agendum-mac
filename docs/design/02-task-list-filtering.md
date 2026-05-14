# Item 2 Design: Task List Filtering UI

Status: design draft, awaiting reviewer cycle.
Branch: `codex/item-2-task-list-filtering` (branched from `feature/mac-prototype` at `c2a6d97`).
Scope reference: `docs/orchestration-plan.md` §Items, item 2.

## 1. Goal

Surface the existing `task.list` filter parameters (`source`, `status`, `project`, `includeSeen`, `limit`) as first-class controls on the dashboard so the user can narrow the loaded task set without code changes. The backend helper already accepts and validates every filter (`Backend/agendum_backend/helper.py:253-282`), and `AgendumBackendClient.listTasks(source:status:project:includeSeen:limit:)` already forwards them (`Sources/AgendumMacCore/BackendClient.swift:215-233`). Today the workflow hard-codes `nil/nil/nil/true/50` (`Sources/AgendumMacWorkflow/TaskWorkflowModel.swift:447-455`); item 2 replaces that with model-resident filter state, makes the controls visible in the leading sidebar, and reloads the task list whenever the user changes a filter. Filter mutations flow through an explicit `applyFilters(_:)` method that is exercised in `AgendumMacWorkflowTests`, matching the testable-action style established for `markSeen`/`markReviewed`/etc. Errors during a filtered reload populate the global `error: PresentedError?`, identical to today's `refresh()` failure path.

## 2. Surface area

Files this implementation will touch:

- `Sources/AgendumMacWorkflow/TaskWorkflowModel.swift`
  - Add a public `TaskListFilters` struct (Equatable, Sendable, with optional `source`/`status`/`project` and concrete `includeSeen`/`limit` defaults that match today's hard-coded values).
  - Add `@Published public private(set) var filters: TaskListFilters` to `BackendStatusModel` (after `taskActionErrors`, line 192).
  - Add a public `applyFilters(_:)` method that updates `filters` and calls `refresh()`.
  - Change `loadTaskItems()` (lines 447-455) to read from `self.filters` instead of using literals.
  - Update `selectWorkspace(id:)` (line 301) to reset `filters` to `.default` before reloading (see §3.4 for rationale).
  - Initializer gains a defaulted `filters: TaskListFilters = .default` parameter so existing call sites compile unchanged.
- `Sources/AgendumMac/AgendumMacApp.swift`
  - Add a `TaskListFiltersPanel` SwiftUI view rendered inside the leading sidebar of `TaskDashboardView` (after the `List(TaskSource.allCases, ...)`, before the `BackendStatusPanel` `safeAreaInset`).
  - Wire each control to a local `@State var pendingFilters: TaskListFilters` mirror that fires `backendStatus.applyFilters(...)` on commit (see §4.3 for the explicit commit/debounce decision).
  - Reset button (`task-list-filter-clear`) restores `.default`.
- `Tests/AgendumMacWorkflowTests/TaskWorkflowModelTests.swift`
  - Extend `FakeBackend.listTasks(...)` to record the last call's arguments as `lastListTasksCall: ListTasksCall?` (a nested struct holding the five fields). The existing `calls` log keeps the bare `"listTasks"` token so existing tests at lines 23, 65, 105, 141, 153, 175, 280 do not change.
  - Add filter-application, filter-clear, filter-composition, workspace-reset, and error-path tests (§5).
- No changes to `Sources/AgendumMacCore/BackendClient.swift`. The `listTasks(...)` signature is reused as-is.
- No changes to `Backend/agendum_backend/helper.py` or `Tests/test_*.py`. The helper's filter handling is already complete and validated (`helper.py:254-268`).
- No new dependencies, no new SwiftPM targets, no new entitlements.

## 3. Workflow target changes

All additions live in `Sources/AgendumMacWorkflow/TaskWorkflowModel.swift`.

### 3.1 `TaskListFilters` struct

```swift
public struct TaskListFilters: Equatable, Sendable {
    public var source: String?
    public var status: String?
    public var project: String?
    public var includeSeen: Bool
    public var limit: Int

    public init(
        source: String? = nil,
        status: String? = nil,
        project: String? = nil,
        includeSeen: Bool = true,
        limit: Int = 50
    ) {
        self.source = source
        self.status = status
        self.project = project
        self.includeSeen = includeSeen
        self.limit = limit
    }

    public static let `default` = TaskListFilters()

    public static let allowedLimits: [Int] = [25, 50, 100, 200]
}
```

Notes:
- `source` and `status` are stored as the raw backend strings (`"pr_authored"`, `"review received"`, etc.) to keep the model layer agnostic of UI presentation. The SwiftUI layer maps them to display labels (§4.2).
- Defaults (`includeSeen: true`, `limit: 50`) match the literals removed from `loadTaskItems()` so behavior is byte-identical when no filter is set.
- `allowedLimits` mirrors the helper's `0 < limit <= 200` validation (`helper.py:265-268`); a `Picker` is used (rather than a free `Stepper`) to keep payloads bounded and avoid accidental large-fetch UX.
- `Equatable` lets tests assert filter state cleanly and lets the SwiftUI commit path detect no-op changes.

### 3.2 Model state

Add to `BackendStatusModel` after line 192:

```swift
@Published public private(set) var filters: TaskListFilters = .default
```

The setter is private; mutation happens only through `applyFilters(_:)` (§3.3) and `selectWorkspace(id:)` (§3.4). This mirrors the existing access pattern for `tasks`, `taskActionErrors`, and `error`.

The designated initializer (line 206-ish) gains:

```swift
filters: TaskListFilters = .default
```

stored as `self.filters = filters`. Existing call sites — the public `convenience init()` and every test that constructs a model — compile unchanged. Tests that need a non-default starting state can pass it explicitly.

### 3.3 `applyFilters(_:)`

```swift
public func applyFilters(_ filters: TaskListFilters) async {
    guard self.filters != filters else { return }
    self.filters = filters
    await refresh()
}
```

Rationale:
- An explicit method (vs `didSet`-on-`filters`) is testable without spinning up a Combine sink, matches the project's existing `async`-action style (`markSeen`, `markReviewed`, etc.), and lets callers `await` the reload to settle before asserting.
- The early-return on equal filters means SwiftUI's `.onChange(of:)` can fire freely without producing duplicate `listTasks` calls when the user re-selects the same value.
- `refresh()` already clears `taskActionErrors` and resets `error` on success and population on failure (lines 282-299); we get the right reload semantics for free without duplicating logic in `applyFilters(_:)`.
- We deliberately do not introduce a separate "reload tasks only" path. `refresh()` already pulls workspace/auth/sync alongside tasks, but those are inexpensive helper round-trips and reusing `refresh()` keeps the failure-recovery story (sync state, auth state) consistent. If profiling later shows a problem, splitting out a `reloadTasksOnly()` is an isolated follow-up.

### 3.4 `loadTaskItems()`

Replace lines 447-455:

```swift
private func loadTaskItems() async throws -> [TaskItem] {
    try await client.listTasks(
        source: filters.source,
        status: filters.status,
        project: filters.project,
        includeSeen: filters.includeSeen,
        limit: filters.limit
    ).map(TaskItem.init)
}
```

This is the only `client.listTasks(...)` call site in the workflow, so every reload path (`refresh`, `selectWorkspace`, `forceSync`, every `performTaskAction(...)`) automatically picks up the active filters. That is the desired behavior: per-task actions (e.g. `markDone`) reload the list to reflect status changes, and after a filter is applied the user expects subsequent reloads to remain filtered until they change it.

### 3.5 Workspace switch resets filters

In `selectWorkspace(id:)` (line 301), insert a filter reset before the `loadTaskItems()` call inside the `do` block (and inside the `catch` block for symmetry with the existing `taskActionErrors = [:]` reset):

```swift
do {
    let selection = try await client.selectWorkspace(namespace: target.namespace)
    workspace = selection.workspace
    auth = selection.auth
    sync = selection.sync
    workspaces = try await client.listWorkspaces()
    filters = .default                    // new
    tasks = []
    tasks = try await loadTaskItems()
    self.error = nil
    taskActionErrors = [:]
} catch {
    filters = .default                    // new
    tasks = []
    taskActionErrors = [:]
    self.error = PresentedError.from(error)
}
```

Rationale:
- Workspaces are independent agendum installations with their own `project` namespace, status distribution, and source mix. A filter pinned to `project: "agendum-mac"` in the base workspace is almost certainly meaningless in another workspace; carrying it across workspaces would surface an empty list and make the user think the new workspace is empty.
- This mirrors the existing pattern at lines 318 and 321 where `taskActionErrors` is reset on workspace switch (the rationale there is identical: per-workspace state should not leak across workspaces).
- The catch-branch reset preserves the "clean slate on workspace switch" invariant even when the helper reports an error mid-switch.

`refresh()` itself does NOT reset filters — manual refresh is "reload current view," not "start over."

### 3.6 Error path

`applyFilters(_:)` invokes `refresh()`, which on failure populates the global `self.error: PresentedError?` and empties `tasks` (lines 294-298). It does NOT touch `self.filters`, so the user's filter state survives the error and they can retry, edit, or clear the filters from the same UI state. Filter-induced errors flow through the existing `BackendStatusPanel` error UI (no SwiftUI changes needed for error rendering).

`applyFilters` does not need to clear `taskActionErrors` itself because the `refresh()` it calls already resets the map on both its success and failure branches (`TaskWorkflowModel.swift` ~lines 293, 296). A filter change is therefore a list-level operation that piggybacks on `refresh()`'s existing reset semantics; reusing the per-task error map for a list-level failure would mis-bucket the error, and the explicit pre-`refresh` window in `applyFilters` is too narrow to matter.

## 4. SwiftUI changes

All in `Sources/AgendumMac/AgendumMacApp.swift`.

### 4.1 Sidebar vs toolbar — sidebar wins

Decision: filters live in the leading sidebar, beneath the `List(TaskSource.allCases, ...)` and above the existing `BackendStatusPanel` `safeAreaInset` (line 45-49). Justification:

- Five controls (status `Picker`, source `Picker`, project `TextField`, includeSeen `Toggle`, limit `Picker`) plus a Clear button do not fit cleanly in the existing toolbar (`AgendumMacApp.swift:56-87`), which already hosts New Task / Refresh / Sync. Cramming them in would either crowd the toolbar or hide them behind a `Menu`, both of which degrade discoverability for the prototype.
- The sidebar already has vertical headroom and is the conventional macOS location for persistent filter affordances (Mail rules, Finder smart-folder predicates, Xcode issue navigator filter bar). It also keeps filter state visually adjacent to the source-picker the user is browsing.
- The sidebar location nests inside the same `NavigationSplitView` column as the source picker, so collapsing the sidebar (already supported by `NavigationSplitView`) hides filters and source list together — a clean affordance for a "I want maximum task pane" workflow.

### 4.2 Controls

A new private `TaskListFiltersPanel` view is added, rendered immediately after the `List(TaskSource.allCases, ...)` block (line 40-43) and before the existing `.safeAreaInset(edge: .bottom)` block. It is wrapped in a `DisclosureGroup("Filters")` so it can be collapsed; `@AppStorage("task-list-filters-expanded")` persists its expansion state across launches (this is a UI-affordance preference, not filter persistence; see §7).

| Field          | Control                                              | Accessibility identifier            |
| -------------- | ---------------------------------------------------- | ----------------------------------- |
| `status`       | `Picker` with `nil` "All" + every value listed in `../agendum/src/agendum/widgets.py:14-29` `STATUS_STYLES` (`draft`, `open`, `awaiting review`, `changes requested`, `review received`, `approved`, `merged`, `review requested`, `reviewed`, `re-review requested`, `backlog`, `in progress`, `closed`, `done`) — note `merged`, `closed`, `done` are the terminal statuses per `../agendum/src/agendum/db.py:6` `TERMINAL_STATUSES = {"merged", "closed", "done"}`. The sibling-checkout requirement is documented in `docs/handoff.md` and CI replicates it via `.github/workflows/test.yml`. Verified against `../agendum` sibling at the time of writing; build phase must re-verify if `../agendum` changes meaningfully. | `task-list-filter-status`           |
| `source`       | `Picker` with `nil` "All" + `pr_authored`, `pr_review`, `issue`, `manual` (per `docs/backend-contract.md` §Shared Types §Task) | `task-list-filter-source`           |
| `project`      | `TextField` (free-form; projects are user-defined per `../agendum/src/agendum/task_api.py:152-169`) — empty string maps to `nil`. Match semantics are exact, case-sensitive (see §7); placeholder text is "Exact match" so users do not assume substring/`LIKE` semantics. | `task-list-filter-project`          |
| `includeSeen`  | `Toggle("Include seen items")`                       | `task-list-filter-include-seen`     |
| `limit`        | `Picker` with `[25, 50, 100, 200]` (matches `TaskListFilters.allowedLimits`) | `task-list-filter-limit`            |
| Clear all      | `Button("Clear filters")` calling `applyFilters(.default)` | `task-list-filter-clear`            |

Rationale for the limit `Picker` (vs `Stepper`):
- The helper validates `0 < limit <= 200` (`helper.py:265-268`); arbitrary user input would be a foot-gun.
- A `Picker` with four sensible values keeps payload bounded and matches the macOS convention for "page size" controls.
- 25/50/100/200 spans the typical small/default/large/max axis without exposing the user to the helper's 200-cap as a UX surprise.

Display labels for `source`/`status` `Picker`s use a lightweight inline mapping (e.g. `"pr_review"` → `"Reviews requested"`), kept private to the SwiftUI file. The model-side string is the raw backend value, so the bridge contract is unchanged.

### 4.3 Commit semantics

To avoid hammering the helper with a `listTasks` round-trip on every keystroke or selection toggle, the panel uses a "commit on change" model with a small structural simplification:

- `Picker`/`Toggle` controls bind to a local `@State var pendingFilters: TaskListFilters` and fire `backendStatus.applyFilters(pendingFilters)` from `.onChange(of: pendingFilters)`. Because `applyFilters` short-circuits on equality, this is fine: the user committing a `Picker` is one mutation, one reload.
- The `project` `TextField` uses `.onSubmit { backendStatus.applyFilters(pendingFilters) }` so the helper round-trip happens on Return / focus-loss, not per-keystroke. The `pendingFilters` mirror still updates as the user types so the visible `TextField` stays responsive.
- The Clear button calls `applyFilters(.default)` directly, then resets `pendingFilters` to `.default`.
- `pendingFilters` is initialized from `backendStatus.filters` on view appear and re-synced via `.onChange(of: backendStatus.filters)` so a `selectWorkspace(...)`-driven reset (§3.5) is reflected in the UI.

We deliberately do NOT add an explicit "Apply" button. The existing `Picker`/`Toggle` controls have unambiguous commit moments; an Apply button would be redundant for them, and the `TextField`'s `.onSubmit` covers the only ambiguous case. This matches the macOS Smart-Folder UX and keeps the panel minimal.

### 4.4 Active-filter indication

We do not add an "active filter" chip count or banner. The control values themselves are the indication: "Status: Review received, Source: All, Project: agendum, …" is visible in the sidebar at all times (when the `DisclosureGroup` is expanded). Adding a chip-count would duplicate that information. The Clear button is always enabled (no-op on default state) so the discoverability cost of finding the reset path stays low. If real users find this confusing in the prototype phase, an inline "N filters active" badge on the `DisclosureGroup` label is a one-line follow-up.

### 4.5 `isLoading` disablement

Filter controls (`Picker`s for status/source/limit, the `Toggle` for `includeSeen`, the `project` `TextField`, and the Clear `Button`) remain ENABLED during `isLoading`. This is a deliberate departure from the existing toolbar buttons (New/Refresh/Sync), which are disabled while a reload is in flight. Rationale: (a) filter controls only mutate workflow state (`self.filters`); the resulting `refresh()` reuses the existing serial `@MainActor` discipline and the equality short-circuit in §3.3, so a control mutation during loading is at worst one extra reload, never a torn state; (b) blocking input during reloads degrades UX more than the rare interleaving cost — a user who notices results are stale and wants to refine the filter should not have to wait for the previous reload to settle; (c) the in-flight overlap race captured in §7 is the residual risk and is explicitly accepted at the prototype bar; (d) the toolbar's New/Refresh/Sync buttons stay disabled because they trigger fresh server work (helper-side `task.create`, `sync.force`, full reload), which is a different concern from filter mutation — those actions are not idempotent under rapid re-fire and can produce duplicate network traffic, while filter mutations are idempotent and bounded.

### 4.6 Interaction with the existing `TaskSource` sidebar list

The leading `List(TaskSource.allCases, ...)` (line 40) is a client-side grouping (`filteredTasks` at line 153 partitions `backendStatus.tasks` by `source`), not a server-side filter. It stays exactly as today. The new `source` filter in the panel is the server-side filter and is independent: the user can server-filter to `pr_review` AND select the "Issues & Manual" sidebar group, which would correctly produce zero rows in the content list. We accept this composition — both filters are useful and orthogonal, the empty result is honest, and the prototype phase does not need to reconcile them. A future checkpoint could either auto-sync the sidebar selection to the server-side `source` filter or hide the sidebar group when a `source` filter is active. Not in scope for item 2.

## 5. Test plan

All new and modified tests in `Tests/AgendumMacWorkflowTests/TaskWorkflowModelTests.swift`. Reuse the existing `FakeBackend` actor and `task(...)` helper.

### 5.1 `FakeBackend` extension

Add a recorded last-call snapshot:

```swift
struct ListTasksCall: Equatable {
    let source: String?
    let status: String?
    let project: String?
    let includeSeen: Bool
    let limit: Int
}

private(set) var lastListTasksCall: ListTasksCall?
```

`listTasks(...)` (line 806) updates `lastListTasksCall` at the top before the `try failIfNeeded` so failure-path tests can still inspect what the model attempted to send. The `calls` log keeps the bare `"listTasks"` token so the lines 23, 65, 105, 141, 153, 175, 280 assertions stay green.

### 5.2 New tests (one-line intents)

1. `testApplyFiltersSendsExactPayload` — apply `TaskListFilters(source: "pr_review", status: "review received", project: "agendum", includeSeen: false, limit: 100)`; assert `backend.lastListTasksCall == ListTasksCall(source: "pr_review", status: "review received", project: "agendum", includeSeen: false, limit: 100)`. Pins the §3.4 forwarding contract field-by-field.
2. `testApplyFiltersTriggersExactlyOneReload` — apply non-default filters once; assert `calls.last == "listTasks"` and `calls.filter { $0 == "listTasks" }.count == 2` (one from the initial `refresh()` setup in the test, plus one from `applyFilters`). Pins the §3.3 "one mutation, one reload" contract.
3. `testApplyFiltersIsNoOpWhenFiltersUnchanged` — call `applyFilters(.default)` on a freshly-`refresh`ed model whose filters are already `.default`; assert no additional `"listTasks"` call appears in `calls`. Pins the early-return guard in §3.3.
4. `testApplyFiltersDefaultClearsAllFilters` — apply non-default filters, then `applyFilters(.default)`; assert `lastListTasksCall == ListTasksCall(source: nil, status: nil, project: nil, includeSeen: true, limit: 50)`. Pins the Clear-button path.
5. `testApplyFiltersComposesAllFiveFields` — covered by #1; the assertion is the composition. Documented separately so the brief's "filters compose" line item maps to a named test.
6. `testSelectWorkspaceResetsFilters` — apply non-default filters, then `selectWorkspace(id: "example-org")`; assert `model.filters == .default` and `lastListTasksCall == ListTasksCall(source: nil, status: nil, project: nil, includeSeen: true, limit: 50)`. Pins §3.5.
7. `testSelectWorkspaceFailureAlsoResetsFilters` — apply non-default filters, then fail `selectWorkspace` via `backend.failNext("selectWorkspace", ...)`; assert `model.filters == .default` and `model.error != nil`. Pins the catch-branch reset.
8. `testApplyFiltersFailureSetsGlobalErrorAndPreservesFilters` — apply non-default filters, then fail the next `listTasks` via `backend.failNext("listTasks", ...)` and apply a different filter set; assert `model.error?.message != nil`, `model.taskActionErrors == [:]` (anchored to `refresh()`'s catch-branch reset at `TaskWorkflowModel.swift:296`, not to a claim that filter mutations leave the map untouched), and `model.filters` reflects the *attempted* (latest) filter set so the user can retry/clear from the same UI state. Pins §3.6.
9. `testRefreshUsesCurrentFilters` — apply non-default filters, `backend.resetCalls()`, call `refresh()`; assert `lastListTasksCall` reflects the previously-applied filters. Pins §3.4 "every reload path picks up active filters."
10. `testForceSyncUsesCurrentFilters` — analogous to #9 but for `forceSync()`. Same pin, different reload path.
11. `testPerformTaskActionReloadUsesCurrentFilters` — analogous to #9 but triggered by `markSeen(id:)`. Confirms per-task actions also respect the active filters via the shared `loadTaskItems()`.
12. `testCreateManualTaskReloadHonorsActiveFilters` — apply non-default filters, `backend.resetCalls()`, call `createManualTask(title: "new", project: nil, tags: nil)` on the success path; assert the resulting reload's `lastListTasksCall` reflects the active (non-default) filters and `tasks` updates accordingly. Confirms `createManualTask`'s post-create reload (`TaskWorkflowModel.swift:415`) also flows through `loadTaskItems()` and therefore respects active filters.
13. `testInitialFiltersAreDefault` — assert `BackendStatusModel().filters == .default` (single line; pins the public initializer contract).
14. `testListTasksDefaultIsByteIdenticalToPriorBehavior` — fresh model, `refresh()`, assert `lastListTasksCall == ListTasksCall(source: nil, status: nil, project: nil, includeSeen: true, limit: 50)`. Guards against accidental default drift.

Existing tests left untouched (verify still pass without modification):
- `testRefreshSuccessLoadsTasks` (line 8) — uses default filters, expects `["currentWorkspace", "listWorkspaces", "authStatus", "syncStatus", "listTasks"]`.
- `testSelectWorkspaceSuccess` (line 45) — expects `["selectWorkspace:example-org", "listWorkspaces", "listTasks"]`.
- `testForceSyncRefreshesTasks` (line 85) — expects `[..., "listTasks"]`.
- `testRefreshFailsWhenWorkspaceFetchFails` and friends — error-path tests that do not inspect `lastListTasksCall`.

The `calls.append("listTasks")` token is preserved exactly, so these tests do not need to change.

### 5.3 Test conventions

- Reuse the `task(...)` helper at line 753 for fixture tasks; backend-side payload contents do not affect filter assertions, so any fixture works.
- Use `XCTAssertEqual(backend.lastListTasksCall, ListTasksCall(...))` for clarity; rely on `Equatable` synthesis on the new struct.
- For workspace-reset tests, populate `backend.setTasks([...])` before the second `loadTaskItems()` call so the success-branch reload exists; this matches the existing `testSelectWorkspaceSuccess` setup at line 45-65.
- Reuse `immediateSleep` (line 667) for any test that flows through `forceSync()` to keep the suite deterministic.

### 5.4 SwiftUI coverage gap

The five accessibility identifiers and the `pendingFilters` `.onChange` / `.onSubmit` wiring are not exercised by SwiftPM tests; no SwiftUI test target exists today (same gap as item 1, see `docs/design/01-open-task-url.md` §5.1.1). The §6 manual smoke covers the SwiftUI layer. Introducing a SwiftUI test target is out of scope for item 2.

## 6. Validation

Per `docs/orchestration-plan.md` §Validation Gates:

- `swift build` passes.
- `swift test --enable-code-coverage` passes; expect `AgendumMacWorkflowTests` test count to grow by +13 tests (#1, #2, #3, #4, #6, #7, #8, #9, #10, #11, #12, #13, #14; #5 is documentation that overlaps with #1). `AgendumMacCoreTests` count is unchanged.
- `/opt/homebrew/bin/python3 -m unittest discover -s Tests` passes (Python helper unchanged; expect identical test count to the post-PR-#17 baseline).
- `/opt/homebrew/bin/python3 Scripts/python_coverage.py` passes (no helper changes; helper coverage stays at the post-PR-#17 baseline ≥ 91%).
- `git diff --check` passes.
- `swift run AgendumMac` smoke-launches without immediate crash, and a manual click-through confirms: setting status to "review received" reduces the visible task list to matching items, clearing filters restores the full set, switching workspace resets all filter controls to their default values, and a `project` filter committed via Return triggers a reload.

No helper protocol surface is touched, so no subprocess JSONL test additions are required (per `docs/orchestration-plan.md` §Validation Gates last bullet).

This change is not service-shaped (no new helper command, no new bridge surface, no IPC additions); per `~/.claude/crew/validation-principles.md` "When to skip" criteria, no change-specific integration-validation script is authored. The existing `swift test` + `swift run` smoke gates fully cover the surface.

## 7. Risks / out-of-scope

- **Persisted filters across launches.** Out of scope. `pendingFilters` and `BackendStatusModel.filters` reset to `.default` on every app launch. `@AppStorage("task-list-filters-expanded")` persists only the `DisclosureGroup` open/closed UI state, not the filter values. Persisting filter values is a separate UX decision (do filters belong to the app, the workspace, or the source-picker selection?) and is deferred to a future checkpoint.
- **Full-text search.** The helper supports `task.search` (`docs/backend-contract.md` §`task.search`) but item 2 only exposes `task.list` filters. A search box is a separate item.
- **Sort order.** The helper does not currently expose sort parameters; adding a sort `Picker` would require helper changes and is out of scope.
- **Saved filter presets.** Not in v0.
- **URL-querystring filter sync.** The app has no deep-link surface today; adding one is out of scope.
- **Helper-side filter additions.** This slice does not change `Backend/agendum_backend/helper.py` or extend the bridge protocol. The five existing filters are sufficient.
- **`source` value drift.** The Picker's `source` options are hard-coded against the four values listed in `docs/backend-contract.md` §Shared Types §Task. If agendum adds a new source value upstream (e.g. `discussion`), the Picker will silently miss it until the Mac app is updated. Acceptable for the prototype; mitigation is the tests in §5 fail closed if the upstream-defined enumeration shifts.
- **`status` value drift.** Same risk as source. The status Picker reads from a hard-coded list derived from `../agendum/src/agendum/widgets.py:14-29` (`STATUS_STYLES`) plus `../agendum/src/agendum/db.py:6` `TERMINAL_STATUSES = {"merged", "closed", "done"}`. The sibling-checkout requirement is documented in `docs/handoff.md` and CI replicates it via `.github/workflows/test.yml`. Verified against `../agendum` sibling at the time of writing; build phase must re-verify if `../agendum` changes meaningfully. Future status values added upstream would need a Mac-app update. Acceptable; failure mode is a missing option in the dropdown, not a wrong query.
- **Empty-project-string sentinel.** The `project` `TextField` maps `""` → `nil` (no filter). Users who intentionally have a project literally named `""` (impossible per agendum normalization, see `Backend/agendum_backend/helper.py:295`) would not be able to filter to it. Not a real-world risk.
- **`@AppStorage` cross-version compatibility.** The `task-list-filters-expanded` key is new; no collision with existing `UserDefaults` keys (existing app uses none today).
- **Back-pressure on rapid filter changes.** A user toggling `Picker`s rapidly produces a series of `applyFilters(...)` calls, each of which awaits a full `refresh()`. The early-return on equal filters prevents duplicate fires for the same value, but rapid distinct values still serialize through `refresh()`. The `BackendStatusPanel.isLoading` indicator already reflects this (lines 56-87 disable refresh/sync during reload). Acceptable for the prototype; debounce can be added in a follow-up if real users complain.
- **Initial-launch filter race.** `TaskDashboardView` calls `await backendStatus.refresh()` in `.task` (line 148); `pendingFilters` is initialized from `backendStatus.filters` on view appear. If the user mutates a control before that initial refresh completes, the resulting `applyFilters` short-circuits if equal or fires a redundant reload. The model's serial-actor execution makes this safe (no torn state); the only visible artifact is one extra reload, which is benign.
- **In-flight `applyFilters` overlap race (deferred).** If `applyFilters(B)` arrives while `applyFilters(A)`'s `refresh()` is still in flight, the two reloads can race. (a) `applyFilters` writes `self.filters` then calls `refresh()`; (b) `BackendStatusModel` is `@MainActor`-isolated, so `refresh()` runs serially per actor hop, but two interleaved `refresh()` calls can still issue overlapping `client.listTasks` requests because each `await` cedes the actor. (c) The resulting behavior — the task list reflects the LATEST filter set, but in-flight responses can interleave so the user briefly sees results from filter A before filter B's results land — is acceptable for the prototype: `self.filters` is correct, the displayed `tasks` converge to the latest filter's response, and no torn state is visible. (d) Future hardening could cancel an in-flight request when filters change (e.g. by tracking the most-recent task and discarding earlier results), deferred to a later checkpoint. We deliberately do not add a test for this; it matches the §7 risk-deferral pattern and the prototype-acceptable bar.
- **`project` filter match semantics.** Verified against `../agendum/src/agendum/task_api.py:84` (`if project is not None and task.get("project") != project: continue`): the `project` filter is **exact-match, case-sensitive** Python string equality on the stored `project` column (a typo or different casing yields an empty list). It is NOT substring/`LIKE`. This semantic is reflected in the §4.2 `TextField` placeholder ("Exact match") so the user is not surprised when typing `Agendum` against a project named `agendum` returns nothing. If we later want substring or case-insensitive semantics, that is a helper-side change (and a contract change), so it is out of scope for item 2.

## 8. Open questions

1. Should `forceSync` reset filters to `.default`? Recommendation in this design: NO. `forceSync` is "pull fresh data from GitHub for the current view," not "start over." Item 2 leaves `forceSync()` (line 326) untouched. Confirm.
2. Should the per-source `TaskSource` sidebar List (line 40) be hidden when a server-side `source` filter is active? Recommendation: NO — see §4.6; both filters compose meaningfully and the prototype should not over-engineer the UX. Confirm.
3. Should `applyFilters(_:)` clear `taskActionErrors`? Recommendation: NO — `refresh()` already resets it on both branches (`TaskWorkflowModel.swift:293, 296`), so `applyFilters` inherits the reset for free; adding a duplicate clear in `applyFilters` would be redundant. Confirm only if reviewer disagrees.

### Self-review (five-lens) pass-throughs

- **Correctness.** The model's `loadTaskItems()` is the single call site for `client.listTasks(...)`; routing it through `self.filters` is sufficient for every reload path. Verified against `TaskWorkflowModel.swift` lines 287, 314, 326-338, 408-435 — every path that reloads tasks does so via `loadTaskItems()`. No orphan call sites.
- **Scope discipline.** Surface area is bounded to one workflow file, one app file, and one tests file. Helper untouched. Bridge contract untouched. No new SwiftPM products. No new entitlements. Matches the orchestration-plan §Branch and PR Discipline rule.
- **Missing risks.** Added §7 entries for status/source value drift, empty-project sentinel, back-pressure, and initial-launch race after first-pass review surfaced them.
- **Test strength.** §5.2 covers the brief's six required cases (apply triggers reload with exact payload; clear-all reloads unfiltered; filters compose; workspace switch resets and reloads; error during filtered reload populates `error`; existing tests pass) plus four guard tests for default drift, error-state filter preservation, and per-action-reload filter respect.
- **Consistency with item 1.** Same eight-section layout. Same anchored-claim style. Same SwiftUI-coverage-gap call-out. Same validation gate enumeration. No structural drift.
