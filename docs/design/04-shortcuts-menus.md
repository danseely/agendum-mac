# Item 4 Design: Keyboard Shortcuts + Menu Coverage

Status: design draft, awaiting reviewer cycle.
Branch: `codex/item-4-shortcuts-menus` (branched from `feature/mac-prototype` at `c4a6b5a`).
Scope reference: `docs/orchestration-plan.md` §Items, item 4.

## 1. Goal

After this lands, a keyboard-only macOS user can drive the entire dashboard from the menu bar: pull-to-refresh, force a sync, open the New-Task sheet, open the focused task in the browser, and run every per-task workflow action (mark seen, mark reviewed, mark in progress, move to backlog, mark done, remove) — each with a memorable shortcut that does not collide with default macOS bindings. The currently-selected task in the dashboard's content list (already tracked as a SwiftUI `@State var selectedTask: TaskItem.ID?` at `Sources/AgendumMac/AgendumMacApp.swift:34`) becomes the implicit subject of every per-task command. The `Task` menu items are correctly enabled or disabled based on (a) whether a task is selected at all and (b) whether the action is in `task.availableDetailActions` for that task (`Sources/AgendumMacWorkflow/TaskWorkflowModel.swift:55-71`), so users see meaningful affordances rather than a sea of always-enabled rows.

The current menu surface is a single `CommandGroup(after: .appInfo)` containing a `Sync Now` button bound to `Cmd-R` (`Sources/AgendumMac/AgendumMacApp.swift:13-23`). That binding is wrong on two counts: (a) `Cmd-R` is the conventional macOS "Refresh" shortcut (Mail, Safari, App Store all use it for reload), not "Sync"; (b) the same `Cmd-R` is therefore unavailable for the toolbar Refresh button (`AgendumMacApp.swift:69-79`) which is the natural "reload" action. Item 4 corrects this and adds the rest of the surface.

## 2. Surface area

Files this implementation will touch:

- `Sources/AgendumMacWorkflow/TaskWorkflowModel.swift`
  - Add `@Published public internal(set) var selectedTaskID: TaskItem.ID?` to `BackendStatusModel` (after `diagnosticsError` at line 224). Mutator visibility is `internal(set)` because the SwiftUI layer in the same module-pair drives it via a `Binding`-bridge; tests in `AgendumMacWorkflowTests` exercise it via the public getter and `setSelectedTaskID(_:)` (see §4.1).
  - Add a `public func setSelectedTaskID(_ id: TaskItem.ID?)` setter, both for SwiftUI (so the dashboard does not need `internal` access from a different module) and as a stable test seam.
  - Extend the `TaskDashboardCommand` enum (line 103) with new cases for `refresh`, `newTask`, `openInBrowser`, `markSeen`, `markReviewed`, `markInProgress`, `moveToBacklog`, `markDone`, `remove`. Each per-task case reads `model.selectedTaskID` inside `perform(on:)`; if nil, the call no-ops. (`refresh` and `sync` already exist.) `newTask` is a special case — see §3.2.
  - Add a `public func availability(on model: BackendStatusModel) -> Bool` instance method on `TaskDashboardCommand` that the SwiftUI `.disabled(...)` modifier reads to decide enablement (see §3.3).
  - Extend the `TaskDashboardCommands` struct (line 118) with named slots for the new menu commands so the SwiftUI layer references one canonical descriptor instead of duplicating literals.
- `Sources/AgendumMac/AgendumMacApp.swift`
  - Replace the existing single `CommandGroup(after: .appInfo)` block (lines 13-23) with a richer `.commands { ... }` modifier: `CommandGroup(replacing: .newItem)` for File-menu shortcuts (New Task, Refresh, Sync Now), and a new top-level `CommandMenu("Task")` for per-task actions.
  - Lift the dashboard's `selectedTask` (`TaskDashboardView` line 34) and `isShowingCreateManualTask` (line 35) up to `AgendumMacApp` as App-level `@State`, and pass each into `TaskDashboardView` as a `@Binding`. This gives the `.commands { ... }` closure direct lexical access to both.
  - Bridge the App-level `selectedTask` into the model via `.onChange(of: selectedTask)` (in `TaskDashboardView`'s body, reading the binding) calling `backendStatus.setSelectedTaskID(selectedTask)`. Single source of truth stays SwiftUI; the model gets a one-way mirror so commands can read it.
  - The `WindowGroup`'s content closure remains structurally unchanged; only the modifier on it changes plus the two new bindings passed in.
- `Tests/AgendumMacWorkflowTests/TaskWorkflowModelTests.swift`
  - Extend the existing `TaskDashboardCommands` test patterns (lines 126-154) to cover every new command's `perform(on:)` and `availability(on:)` semantics. Mirror the existing one-line direct-invocation style — do NOT introduce SwiftUI rendering tests.

No changes expected to:

- `Backend/agendum_backend/helper.py` or any Python tests. The helper protocol is untouched; menus only re-route to existing model methods.
- `Sources/AgendumMacCore/BackendClient.swift`. No new client methods.
- `Sources/AgendumMacWorkflow/TaskWorkflowModel.swift` per-task action methods (`markSeen`, `markReviewed`, etc., lines 384-446). Their bodies are exactly what the menu commands invoke.
- `Package.swift`. No new targets, no new products.
- `docs/backend-contract.md`. No bridge surface changes.
- `Tests/test_backend_helper.py`, `Tests/test_backend_helper_process.py`. No helper protocol changes.

## 3. Menu structure and shortcuts

### 3.1 Top-level menus extended

Three menu surfaces gain entries:

| macOS menu | Insertion strategy                                            | Items                                |
| ---------- | ------------------------------------------------------------- | ------------------------------------ |
| File       | `CommandGroup(replacing: .newItem)`                           | New Task, Refresh, Sync Now          |
| Task (new) | `CommandMenu("Task")`                                         | Open in Browser, Mark Seen, Mark Reviewed, Mark In Progress, Move to Backlog, Mark Done, Remove |
| Settings   | inherited macOS-default `Cmd-,`                               | (no change; `Settings` scene already wires `Cmd-,`) |

We deliberately replace `.newItem` rather than appending to it because (a) SwiftUI's default `New` menu items (`New Window`, `New File`) do not apply to this app, and (b) replacing keeps the File menu uncluttered. The replacement is documented as Apple's intended path (`CommandGroupPlacement.newItem`).

### 3.2 Shortcut table

| Menu | Item              | Shortcut    | Bound to                                         | Disabled when                                         | Identifier                          |
| ---- | ----------------- | ----------- | ------------------------------------------------ | ----------------------------------------------------- | ----------------------------------- |
| File | New Task          | `Cmd-N`     | `commands.menuNewTask` (opens sheet, see §4.4)   | `backendStatus.isLoading`                             | `menu-action-new-task`              |
| File | Refresh           | `Cmd-R`     | `commands.menuRefresh.perform`                   | `backendStatus.isLoading`                             | `menu-action-refresh`               |
| File | Sync Now          | `Cmd-Shift-S` | `commands.menuSync.perform`                    | `backendStatus.isLoading`                             | `menu-action-sync`                  |
| Task | Open in Browser   | `Cmd-Shift-L` | `commands.menuOpenInBrowser.perform`           | no selection OR `.openBrowser ∉ availableDetailActions` | `menu-action-open-browser`        |
| Task | Mark Seen         | `Cmd-Opt-M` | `commands.menuMarkSeen.perform`                  | no selection OR `.markSeen ∉ availableDetailActions`  | `menu-action-mark-seen`             |
| Task | Mark Reviewed     | `Cmd-Opt-R` | `commands.menuMarkReviewed.perform`              | no selection OR `.markReviewed ∉ availableDetailActions` | `menu-action-mark-reviewed`     |
| Task | Mark In Progress  | `Cmd-Opt-I` | `commands.menuMarkInProgress.perform`            | no selection OR `.markInProgress ∉ availableDetailActions` | `menu-action-mark-in-progress` |
| Task | Move to Backlog   | `Cmd-Opt-B` | `commands.menuMoveToBacklog.perform`             | no selection OR `.moveToBacklog ∉ availableDetailActions` | `menu-action-move-to-backlog`  |
| Task | Mark Done         | `Cmd-Opt-D` | `commands.menuMarkDone.perform`                  | no selection OR `.markDone ∉ availableDetailActions`  | `menu-action-mark-done`             |
| Task | Remove            | `Cmd-Shift-Backspace` | `commands.menuRemove.perform`          | no selection OR `.remove ∉ availableDetailActions`    | `menu-action-remove`                |

### 3.3 Collisions considered

Each shortcut was checked against macOS system-default bindings (per Apple's Human Interface Guidelines "Keyboard Shortcuts" appendix and the `CommandGroup` defaults baked into SwiftUI):

- `Cmd-N` (New Task) — system default for `.newItem`. We replace `.newItem` so this is the only binding for Cmd-N in our app; no collision.
- `Cmd-R` (Refresh) — universal "reload" convention (Safari, Mail, App Store, Xcode). Frees up the slot by relocating the previous `Sync Now / Cmd-R` binding to `Cmd-Shift-S`. No system collision; the only collision is with the prior in-app binding, which we are deliberately fixing.
- `Cmd-Shift-S` (Sync Now) — `.saveItem`'s default would be `Cmd-S`, and `Cmd-Shift-S` defaults to `Save As…`. We do not have a Save menu item (no document model), and replacing `.saveItem` is unnecessary because the app exposes no Save command; SwiftUI does not synthesize a Save item without `DocumentGroup`. No collision in practice.
- `Cmd-Shift-L` (Open in Browser) — Safari uses `Cmd-Shift-L` for "Search the Web…" but only when Safari is frontmost; `Cmd-L` is "focus address bar" in Safari but our app has no equivalent. No collision in our context.
- `Cmd-Opt-{M,R,I,B,D}` (per-task actions) — the `Cmd-Opt` modifier space is sparsely used by macOS defaults. `Cmd-Opt-M` minimizes-all in some apps via Window menu (`.windowList`); we accept the collision only when the Task menu item is disabled (no selection), in which case the menu binding does not consume the keystroke. When the Task menu item is enabled, our binding wins because per-app `CommandMenu` shortcuts take precedence over the system Window menu's defaults.
- `Cmd-Shift-Backspace` (Remove) — Finder's "Move to Trash" lives at `Cmd-Backspace`, but using `Cmd-Backspace` here is unsafe: menu key equivalents are matched ahead of the responder chain, so with focus inside a TextField (the project-filter field, the New Task sheet's title field) and a task selected, `Cmd-Backspace` would fire the menu's Remove action rather than the field's "delete to start of line" editing operation. Adding `Shift` sidesteps this entire collision class — `Cmd-Shift-Backspace` is not a default text-editing binding in any field type SwiftUI ships, so the menu wins unambiguously and editing keys are not hijacked. The `.disabled(...)` predicate still gates on selection so the keystroke is ignored when no removable task is selected. The trade-off is that we move one step away from Finder's exact idiom; in exchange we avoid the unsafe-edit class entirely.

If real users surface a collision with their own app set, we can rebind without a contract change. The bindings live in one file (`Sources/AgendumMac/AgendumMacApp.swift`); rebinding is a one-line change per item.

### 3.4 Disabled-state rationale

Per-task menu items appear permanently in the Task menu (always visible) but are disabled when the action is unavailable. This is conventional macOS UX: hiding menu items based on context fragments the menu structure across launches and degrades discoverability. SwiftUI's `Button(...).disabled(...)` greys out the row and ignores the keystroke; the user sees the action exists but is not currently applicable.

## 4. Workflow target changes

All additions in `Sources/AgendumMacWorkflow/TaskWorkflowModel.swift`.

### 4.1 Selection seam

Add to `BackendStatusModel` after line 224:

```swift
@Published public internal(set) var selectedTaskID: TaskItem.ID?
```

Plus a public setter for SwiftUI cross-module call sites:

```swift
public func setSelectedTaskID(_ id: TaskItem.ID?) {
    selectedTaskID = id
}
```

Justification:
- The dashboard already tracks selection in SwiftUI via `@State var selectedTask: TaskItem.ID?` (currently at `AgendumMacApp.swift:34`, lifted to the App level by §5.1). That state remains the source of truth — it drives the `List(selection:)` binding and the detail-pane content. We do NOT relocate it onto the model; we mirror it so commands can read it.
- A setter (rather than a published property the dashboard binds to directly) preserves the existing pattern that all model state is `private(set)` outside the model itself. The dashboard pushes selection changes via `.onChange(of: selectedTask) { backendStatus.setSelectedTaskID($0) }`. After §5.1's lift, both the App-level `selectedTask` `@State` and any menu-driven mutation (e.g. Refresh setting `selectedTask = nil`) flow through the same binding and `.onChange`, so the model mirror has exactly one writer.
- `internal(set)` keeps the contract: tests in the workflow target (same module) can assert against `selectedTaskID` without extra plumbing; the SwiftUI layer in the app target uses the public setter.
- We deliberately do NOT clear `selectedTaskID` inside `removeTask`/`markReviewed`/`markDone` (which already null out the SwiftUI selection at `AgendumMacApp.swift:119,131,137`). The SwiftUI layer's `selectedTask = nil` triggers `.onChange` which calls `setSelectedTaskID(nil)`. Single ownership, no duplicate clearing inside model methods.

### 4.2 `TaskDashboardCommand` enum extension

Replace the existing two-case enum (line 103) with:

```swift
public enum TaskDashboardCommand: Hashable, Sendable {
    case refresh
    case sync
    case newTask
    case openInBrowser
    case markSeen
    case markReviewed
    case markInProgress
    case moveToBacklog
    case markDone
    case remove

    @MainActor
    public func perform(on model: BackendStatusModel) async {
        switch self {
        case .refresh:
            await model.refresh()
        case .sync:
            await model.forceSync()
        case .newTask:
            // Sheet presentation lives in SwiftUI; the command is a no-op
            // when invoked directly. The SwiftUI layer reads
            // `commands.menuNewTask` only as an availability + identifier
            // descriptor and triggers the sheet via a separate
            // @State. See §4.4.
            return
        case .openInBrowser:
            guard let id = model.selectedTaskID else { return }
            await model.openTaskURL(id: id)
        case .markSeen:
            guard let id = model.selectedTaskID else { return }
            await model.markSeen(id: id)
        case .markReviewed:
            guard let id = model.selectedTaskID else { return }
            await model.markReviewed(id: id)
        case .markInProgress:
            guard let id = model.selectedTaskID else { return }
            await model.markInProgress(id: id)
        case .moveToBacklog:
            guard let id = model.selectedTaskID else { return }
            await model.moveToBacklog(id: id)
        case .markDone:
            guard let id = model.selectedTaskID else { return }
            await model.markDone(id: id)
        case .remove:
            guard let id = model.selectedTaskID else { return }
            await model.removeTask(id: id)
        }
    }
}
```

The `guard let id = model.selectedTaskID else { return }` pattern is the explicit no-op contract from §3.4: when nothing is selected, `perform` returns silently without mutating model state. The SwiftUI `.disabled(...)` predicate (§5.2) prevents the menu item from firing in that case anyway, so this guard is defensive and tested (§6).

### 4.3 `availability(on:)` predicate

Add an instance method that the SwiftUI `.disabled(...)` modifier reads:

```swift
@MainActor
public func availability(on model: BackendStatusModel) -> Bool {
    switch self {
    case .refresh, .sync, .newTask:
        return !model.isLoading
    case .openInBrowser:
        return perTaskAvailable(.openBrowser, on: model)
    case .markSeen:
        return perTaskAvailable(.markSeen, on: model)
    case .markReviewed:
        return perTaskAvailable(.markReviewed, on: model)
    case .markInProgress:
        return perTaskAvailable(.markInProgress, on: model)
    case .moveToBacklog:
        return perTaskAvailable(.moveToBacklog, on: model)
    case .markDone:
        return perTaskAvailable(.markDone, on: model)
    case .remove:
        return perTaskAvailable(.remove, on: model)
    }
}

@MainActor
private func perTaskAvailable(
    _ action: TaskDetailAction,
    on model: BackendStatusModel
) -> Bool {
    guard
        let id = model.selectedTaskID,
        let task = model.tasks.first(where: { $0.id == id })
    else {
        return false
    }
    return task.availableDetailActions.contains(action)
}
```

Notes:
- `availability` is the single source of truth for "should this menu item be enabled". The SwiftUI `.disabled(!command.availability(on: model))` invocation produces the negation locally; this is a small idiom inversion but avoids encoding "disabled when …" semantics in the workflow target.
- Per-task availability composes the two gates in §3.2: selection presence AND `availableDetailActions` membership. Both are read off the model so the menu reflects live model state without SwiftUI having to mirror anything.
- `refresh`, `sync`, and `newTask` reuse the existing `isLoading` gate — same posture as the toolbar buttons (`AgendumMacApp.swift:67,78,89`).

### 4.4 `newTask` is a SwiftUI-driven sheet

The existing toolbar button at `AgendumMacApp.swift:62-67` presents the New Task sheet via `@State private var isShowingCreateManualTask: Bool` (line 35). The menu item must do the same. Two options were considered:

- (a) Add a `@Published var isPresentingCreateManualTask: Bool` to `BackendStatusModel` so `newTask` flips it from `perform(on:)`.
- (b) Have the menu `Button` flip the existing `@State` directly, and `commands.menuNewTask` exists only as an availability descriptor (and identifier).

Option (b) wins. Sheet presentation is presentation-layer state that does not belong on the workflow model, and SwiftUI's `.commands { ... }` closure has lexical access to the dashboard's `@State` via the App-level wrapper. The `Button` body in the File menu reads `isShowingCreateManualTask = true` directly, just like the toolbar button. `commands.menuNewTask.perform(on:)` is implemented as a no-op for symmetry but is never invoked from production; the test in §6 documents this.

Implementation note on lexical access: the existing `@State` lives on `TaskDashboardView` (line 35), which is the `WindowGroup`'s content. The `.commands { ... }` modifier is on the `WindowGroup`, not on `TaskDashboardView`, so the `@State` is not directly visible to the Commands closure. The minimal fix is to lift `isShowingCreateManualTask` to the App level (alongside `backendStatus` at `AgendumMacApp.swift:6`) and pass it down to `TaskDashboardView` via a `Binding`. We do the same for `selectedTask` (currently `TaskDashboardView` line 34) so the menu's Refresh command can write `selectedTask = nil` directly and have the change propagate through the binding into both `List(selection:)` and the model mirror via the existing `.onChange`. Both lifts add `@Binding var isShowingCreateManualTask: Bool` and `@Binding var selectedTask: TaskItem.ID?` parameters to `TaskDashboardView`; the existing toolbar button (line 63) and the `List(selection:)` (line 55) continue to read/write the bindings unchanged. The Commands closure can then read and write the App-level `@State` directly.

### 4.5 `TaskDashboardCommands` struct extension

Extend the struct at line 118 with named slots for each new menu command:

```swift
public struct TaskDashboardCommands: Equatable, Sendable {
    public let toolbarRefresh: TaskDashboardCommand
    public let toolbarSync: TaskDashboardCommand
    public let menuRefresh: TaskDashboardCommand
    public let menuSync: TaskDashboardCommand
    public let menuNewTask: TaskDashboardCommand
    public let menuOpenInBrowser: TaskDashboardCommand
    public let menuMarkSeen: TaskDashboardCommand
    public let menuMarkReviewed: TaskDashboardCommand
    public let menuMarkInProgress: TaskDashboardCommand
    public let menuMoveToBacklog: TaskDashboardCommand
    public let menuMarkDone: TaskDashboardCommand
    public let menuRemove: TaskDashboardCommand

    public static let standard = TaskDashboardCommands(
        toolbarRefresh: .refresh,
        toolbarSync: .sync,
        menuRefresh: .refresh,
        menuSync: .sync,
        menuNewTask: .newTask,
        menuOpenInBrowser: .openInBrowser,
        menuMarkSeen: .markSeen,
        menuMarkReviewed: .markReviewed,
        menuMarkInProgress: .markInProgress,
        menuMoveToBacklog: .moveToBacklog,
        menuMarkDone: .markDone,
        menuRemove: .remove
    )
}
```

Existing call sites (`menuSync`, `toolbarRefresh`, `toolbarSync`) keep their current values. The struct grows but is back-compatible because every consumer accesses fields by name. The existing `testDashboardCommandsShareSyncPath` test (line 126) asserts `menuSync == .sync` and `toolbarSync == .sync`; it stays green unmodified.

### 4.6 Composition with existing flows

- `refresh()` and `forceSync()` are unchanged. The `menuRefresh`/`menuSync` commands route to the same methods the toolbar buttons already route to.
- Per-task action methods (`markSeen`, `markReviewed`, etc.) are unchanged. Their existing `taskActionErrors` semantics, list-reload-on-success behavior, and `isLoading` toggling carry through to the menu invocation path automatically.
- `selectWorkspace(...)` (line 343) does not need to clear `selectedTaskID`: the SwiftUI `selectedTask = nil` clear at `AgendumMacApp.swift:50` (inside the `BackendStatusPanel` workspace-switch callback) flows through `.onChange` to `setSelectedTaskID(nil)`. Single ownership, single clearing path.

## 5. SwiftUI changes

All in `Sources/AgendumMac/AgendumMacApp.swift`.

### 5.1 App-level `@State` lift for new-task sheet and selection

Add two `@State` properties to `AgendumMacApp` (after line 7):

```swift
@State private var isShowingCreateManualTask = false
@State private var selectedTask: TaskItem.ID? = nil
```

Pass both into `TaskDashboardView` as bindings:

```swift
TaskDashboardView(
    backendStatus: backendStatus,
    commands: commands,
    isShowingCreateManualTask: $isShowingCreateManualTask,
    selectedTask: $selectedTask
)
```

In `TaskDashboardView`, replace:
- `@State private var isShowingCreateManualTask = false` (line 35) with `@Binding var isShowingCreateManualTask: Bool`.
- `@State var selectedTask: TaskItem.ID?` (line 34) with `@Binding var selectedTask: TaskItem.ID?`.

Existing call sites read/write the bindings unchanged: the toolbar New Task button (line 63) and sheet presentation (line 92) flip `isShowingCreateManualTask`; the `List(selection: $selectedTask)` (line 55), the workspace-switch callback `selectedTask = nil` (line 50), and the detail-pane post-action clears (lines 119, 131, 137) all continue to operate on the binding.

The `.onChange(of: selectedTask)` mirror push to `backendStatus.setSelectedTaskID(_:)` lives on `TaskDashboardView`'s body (§5.3) — that view already reads `selectedTask` to render the detail pane and to drive `List(selection:)`, so co-locating the mirror there minimises the App-level diff. The App layer only owns the `@State` (so the menu's Refresh command can write `selectedTask = nil` directly) and is unaware of the model mirror.

### 5.2 Commands modifier replacement

Replace lines 13-23 with:

```swift
.commands {
    CommandGroup(replacing: .newItem) {
        Button("New Task") {
            isShowingCreateManualTask = true
        }
        .keyboardShortcut("n", modifiers: [.command])
        .disabled(!commands.menuNewTask.availability(on: backendStatus))
        .accessibilityIdentifier("menu-action-new-task")

        Button("Refresh") {
            selectedTask = nil  // matches toolbar Refresh behavior at line 71; propagates through the binding into both List(selection:) and the model mirror via .onChange in §5.3
            Task {
                await commands.menuRefresh.perform(on: backendStatus)
            }
        }
        .keyboardShortcut("r", modifiers: [.command])
        .disabled(!commands.menuRefresh.availability(on: backendStatus))
        .accessibilityIdentifier("menu-action-refresh")

        Button("Sync Now") {
            Task {
                await commands.menuSync.perform(on: backendStatus)
            }
        }
        .keyboardShortcut("s", modifiers: [.command, .shift])
        .disabled(!commands.menuSync.availability(on: backendStatus))
        .accessibilityIdentifier("menu-action-sync")
    }

    CommandMenu("Task") {
        taskMenuButton(
            title: "Open in Browser",
            command: commands.menuOpenInBrowser,
            backendStatus: backendStatus,
            shortcut: ("l", [.command, .shift]),
            identifier: "menu-action-open-browser"
        )
        Divider()
        taskMenuButton(
            title: "Mark Seen",
            command: commands.menuMarkSeen,
            backendStatus: backendStatus,
            shortcut: ("m", [.command, .option]),
            identifier: "menu-action-mark-seen"
        )
        taskMenuButton(
            title: "Mark Reviewed",
            command: commands.menuMarkReviewed,
            backendStatus: backendStatus,
            shortcut: ("r", [.command, .option]),
            identifier: "menu-action-mark-reviewed"
        )
        taskMenuButton(
            title: "Mark In Progress",
            command: commands.menuMarkInProgress,
            backendStatus: backendStatus,
            shortcut: ("i", [.command, .option]),
            identifier: "menu-action-mark-in-progress"
        )
        taskMenuButton(
            title: "Move to Backlog",
            command: commands.menuMoveToBacklog,
            backendStatus: backendStatus,
            shortcut: ("b", [.command, .option]),
            identifier: "menu-action-move-to-backlog"
        )
        taskMenuButton(
            title: "Mark Done",
            command: commands.menuMarkDone,
            backendStatus: backendStatus,
            shortcut: ("d", [.command, .option]),
            identifier: "menu-action-mark-done"
        )
        Divider()
        taskMenuButton(
            title: "Remove",
            command: commands.menuRemove,
            backendStatus: backendStatus,
            shortcut: (KeyEquivalent.delete, [.command, .shift]),
            identifier: "menu-action-remove"
        )
    }
}
```

Where `taskMenuButton(...)` is a file-scope free function in `AgendumMacApp.swift` (not a method on `AgendumMacApp`, since `AgendumMacApp` conforms to `App`, not `View`, and a `@ViewBuilder` instance method on an `App` type reads oddly). The function takes the model and the binding as explicit parameters:

```swift
@ViewBuilder
private func taskMenuButton(
    title: String,
    command: TaskDashboardCommand,
    backendStatus: BackendStatusModel,
    shortcut: (key: KeyEquivalent, modifiers: EventModifiers),
    identifier: String
) -> some View {
    Button(title) {
        Task {
            await command.perform(on: backendStatus)
        }
    }
    .keyboardShortcut(shortcut.key, modifiers: shortcut.modifiers)
    .disabled(!command.availability(on: backendStatus))
    .accessibilityIdentifier(identifier)
}
```

Each call site in the `CommandMenu("Task")` block passes `backendStatus: backendStatus` alongside the title/command/shortcut/identifier. The `(key: KeyEquivalent, modifiers: EventModifiers)` tuple keeps the per-row binding self-contained so the call sites read like a table.

### 5.3 Selection bridge

Add to `TaskDashboardView.body` (after the existing `.task { ... }` at line 152):

```swift
.onChange(of: selectedTask) { _, newValue in
    backendStatus.setSelectedTaskID(newValue)
}
```

Notes:
- `.onChange(of: selectedTask)` is the only mirror push. The model's `selectedTaskID` is a `@Published` optional whose default is `nil`, matching the App-level `selectedTask` `@State` default of `nil`; the two start in sync without an `.onAppear` priming step. The first non-`nil` selection (user click, menu invocation, etc.) fires `.onChange` and brings the mirror into agreement.
- We use the iOS-17/macOS-14 two-parameter `.onChange` signature — already used elsewhere in the codebase (per the macOS-14 baseline implied by `Settings { ... }` and `LabeledContent` adoption in `SettingsView`).
- We do NOT bind `List(selection:)` directly to `backendStatus.selectedTaskID`. The SwiftUI `@State` (lifted to App level per §5.1) stays the source of truth; the model is a one-way mirror that menus read.

### 5.4 Identifier convention

`menu-action-*` is a new prefix. It does not collide with the existing `task-action-*`, `task-list-filter-*`, `sync-status-*`, `settings-*`, or `task-list-create-*` namespaces (verified by grep against the surface listed in PR #19's handoff). Each menu item carries its identifier so a future SwiftUI test target can drive the menu by ID without rediscovering the binding.

## 6. Test plan

All in `Tests/AgendumMacWorkflowTests/TaskWorkflowModelTests.swift`. Mirror the existing `testDashboardCommandsShareSyncPath` (line 126) and `testDashboardRefreshCommandUsesRefreshPath` (line 144) patterns — direct invocation of the command's `perform(on:)`, no SwiftUI rendering.

Selection-seam tests seed the mirror via the public setter `model.setSelectedTaskID(_:)`, exercising the same entry point the SwiftUI `.onChange(of: selectedTask)` (§5.3) calls in production. We keep the test target inside the workflow module rather than the app target because (a) the workflow target already has the `FakeBackend` and fixture infrastructure, and (b) the App-level `@State` lift in §5.1 is purely a SwiftUI lexical-access concern; the model contract under test (the `selectedTaskID` mirror plus `perform(on:)` and `availability(on:)`) is identical regardless of who pushes the setter. Tests that explicitly cover the binding-to-mirror round trip (§6.2 #1, #2) operate directly on the model setter; the `.onChange` push is verified by §7's manual smoke and visual source review per §6.3's existing posture on SwiftUI-binding-shaped behaviour.

### 6.1 Test infrastructure

No new fakes required. Reuse:

- `FakeBackend` (existing) for backend stubs.
- `task(id:title:source:status:url:seen:)` helper (existing, ~line 753) for fixtures.
- `RecordingURLOpener` from `docs/design/01-open-task-url.md` §5.1 for the `openInBrowser` command.
- `immediateSleep` (~line 667) for `forceSync`-routed tests.

### 6.2 New tests (one-line intents)

Selection seam:

1. `testSetSelectedTaskIDUpdatesPublishedValue` — call `model.setSelectedTaskID(17)`, assert `model.selectedTaskID == 17`; call again with `nil`, assert `model.selectedTaskID == nil`. Pins §4.1's setter contract.
2. `testInitialSelectedTaskIDIsNil` — fresh model; assert `model.selectedTaskID == nil`. Single-line guard against accidental default drift.

Per-task command routing:

3. `testMenuOpenInBrowserCommandInvokesOpenTaskURLForSelectedTask` — populate `tasks` with a URL-bearing task `id=42`, set `selectedTaskID = 42`, call `commands.menuOpenInBrowser.perform(on: model)`; assert `RecordingURLOpener.opened` recorded the task's URL exactly once.
4. `testMenuMarkSeenCommandInvokesMarkSeenForSelectedTask` — populate an unseen task `id=42`, set selection, call `commands.menuMarkSeen.perform(on:)`; assert `backend.calls.contains("markTaskSeen:42")`.
5. `testMenuMarkReviewedCommandInvokesMarkReviewedForSelectedTask` — analogous.
6. `testMenuMarkInProgressCommandInvokesMarkInProgressForSelectedTask` — analogous.
7. `testMenuMoveToBacklogCommandInvokesMoveToBacklogForSelectedTask` — analogous.
8. `testMenuMarkDoneCommandInvokesMarkDoneForSelectedTask` — analogous.
9. `testMenuRemoveCommandInvokesRemoveTaskForSelectedTask` — analogous (asserts `backend.calls.contains("removeTask:42")`).

Per-task command no-op when no selection:

10. `testMenuPerTaskCommandsNoOpWhenNoSelection` — table-driven over the seven per-task `TaskDashboardCommand` values; for each, assert with `selectedTaskID = nil` that `perform(on:)` does not append the corresponding `markTaskSeen`/etc. token to `backend.calls` (only the initial `refresh()` setup tokens are present). Pins §4.2's `guard let id` contract.

Per-task command targets the right task:

11. `testMenuMarkSeenCommandTargetsSelectedTaskNotFirstTask` — populate two tasks `id=10` and `id=42`, set `selectedTaskID = 42`, call `commands.menuMarkSeen.perform(on:)`; assert `backend.calls.contains("markTaskSeen:42")` and NOT `markTaskSeen:10`. Pins that the menu reads selection (not implicit first-task).

Availability gating:

12. `testPerTaskCommandAvailabilityFalseWhenNoSelection` — fresh model with populated `tasks`, no selection; assert every per-task `availability(on:)` returns false.
13. `testPerTaskCommandAvailabilityFalseWhenSelectedTaskNotInList` — set `selectedTaskID = 999` (no such task in `tasks`); assert every per-task `availability(on:)` returns false. Pins the `tasks.first(where:)` guard in §4.3.
14. `testOpenInBrowserAvailabilityHonorsAvailableDetailActions` — populate one task with `url != nil` and one with `url == nil`. Select each in turn; assert `commands.menuOpenInBrowser.availability(on:)` is true for the URL-bearing task and false for the URL-less one. Pins composition with `availableDetailActions.contains(.openBrowser)`.
15. `testMarkSeenAvailabilityHonorsAvailableDetailActions` — populate an unseen task and a seen task; assert availability tracks `availableDetailActions.contains(.markSeen)`.
16. `testMarkReviewedAvailabilityHonorsSourceGate` — populate a `pr_review` task and a `pr_authored` task; assert `menuMarkReviewed.availability` is true for the review task and false for the authored task, mirroring the §4.3 composition.
17. `testMarkInProgressAndMoveToBacklogAvailabilityToggleByStatus` — populate a `manual` task with `status == "in progress"` and one with `status == "open"`; assert `menuMarkInProgress.availability` toggles consistent with `availableDetailActions` (which inserts `.moveToBacklog` for in-progress and `.markInProgress` otherwise, see TaskWorkflowModel.swift:67).
18. `testMarkDoneAndRemoveAvailabilityForManualTask` — populate a `manual` task; assert `menuMarkDone.availability == true` and `menuRemove.availability == true`. For a `pr_review` task, assert `menuMarkDone.availability == false` (per `availableDetailActions` not inserting `.markDone` for review tasks) and `menuRemove.availability == true` (every task can be removed).

Special cases:

19. `testNewTaskCommandPerformIsNoOp` — call `commands.menuNewTask.perform(on: model)`; assert `backend.calls` is unchanged. Documents §4.4's "perform is intentionally a no-op; SwiftUI flips the sheet binding directly".
20. `testNewTaskCommandAvailabilityTracksIsLoading` — assert `menuNewTask.availability(on: model) == true` for a fresh model and `false` while loading. Same posture as Refresh/Sync.
21. `testStandardCommandsExposesEveryNamedSlot` — assert `TaskDashboardCommands.standard` has the eleven new fields populated with their canonical case values. One-line guard against accidental refactors that drop a slot.

A `testRefreshAndSyncCommandsAvailableUntilLoading` test was considered and dropped: `BackendStatusModel.isLoading` is `private(set)` and only mutated inside `refresh()`/`forceSync()`/per-task action methods, so a direct toggle from a test would require either a new test seam or a controlled-suspension stub. The existing `refresh`/`forceSync` tests already exercise the `isLoading` gate transitively (the methods set and clear `isLoading` around their work), so an additional command-availability test would either restate the same invariant or introduce plumbing solely for this assertion.

Existing tests preserved:

- `testDashboardCommandsShareSyncPath` (line 126) — already asserts `menuSync == .sync` and `toolbarSync == .sync`; both stay true under §4.5.
- `testDashboardRefreshCommandUsesRefreshPath` (line 144) — already asserts `toolbarRefresh.perform(on:)` reloads tasks; unchanged.

### 6.3 Tests explicitly NOT in scope

We do not write tests that assert literal `KeyEquivalent` bindings (e.g. "Refresh is bound to `Cmd-R`"). SwiftUI's `.keyboardShortcut(...)` modifier is opaque from the view's `body` representation — the produced `Modified<...>` view does not expose the bound key in any way that `XCTest` can introspect without spinning up an `NSApplication` and sending real key events. The shortcut bindings are verified by §7's manual smoke (launching the app and exercising the menu) and by visual review of the `.commands { ... }` source. Future hardening: introduce a SwiftUI / `XCUITest`-based test target that sends synthetic key events; deferred per the existing project posture (no SwiftUI test target today; see `docs/design/01-open-task-url.md` §5.1.1, `docs/design/02-task-list-filtering.md` §5.4, `docs/design/03-settings-auth-repair.md` §6.5).

### 6.4 Test conventions

- Reuse `XCTAssertEqual(opener.opened.map(\.absoluteString), [...])` for URL assertions (item 1 §5.3).
- Use `await backend.calls` after `perform(on:)` returns; the existing `FakeBackend` actor records call tokens like `markTaskSeen:42`.
- For availability tests, prefer direct invocation `command.availability(on: model)` over `XCTAssertFalse(command.availability(on: model))` so the failure message includes the actual bool returned.
- Use `model.setSelectedTaskID(42)` rather than reaching into `selectedTaskID` directly — the test exercises the same setter the SwiftUI layer uses.

## 7. Validation

Per `docs/orchestration-plan.md` §Validation Gates:

- `swift build` passes.
- `swift test --enable-code-coverage` passes; expect `AgendumMacWorkflowTests` count to grow by +21 tests (#1-#21 in §6.2). `AgendumMacCoreTests` count is unchanged.
- `/opt/homebrew/bin/python3 -m unittest discover -s Tests` passes (Python helper unchanged).
- `/opt/homebrew/bin/python3 Scripts/python_coverage.py` passes (no helper changes; coverage stays at the post-PR-#19 baseline ≥ 91%).
- `git diff --check` passes.
- `swift run AgendumMac` smoke-launches without immediate crash, and a manual click-through confirms each menu shortcut works:
  - `Cmd-N` opens the New Task sheet.
  - `Cmd-R` refreshes the dashboard.
  - `Cmd-Shift-S` runs Sync Now.
  - `Cmd-Shift-L` opens the selected task's URL (when one is selected with a URL).
  - `Cmd-Opt-{M,R,I,B,D}` performs the corresponding per-task action when applicable.
  - `Cmd-Shift-Backspace` removes the selected task (and only when a removable task is selected; with a TextField focused, the editing field still receives normal backspace/delete keystrokes).
  - With no task selected, every Task-menu item is greyed out and the keystroke is ignored.

This change is not service-shaped (no new helper command, no new bridge surface, no IPC additions, no new I/O paths). Per `~/.claude/crew/validation-principles.md` "When to skip" criteria, no change-specific integration-validation script is authored. The existing `swift test` gates plus the §7 manual menu smoke fully cover the surface.

## 8. Risks / out-of-scope

- **Editable shortcuts.** Out of scope. macOS's System Settings → Keyboard → Shortcuts already lets users override app menu shortcuts; we do not need an in-app affordance.
- **Command palette (`Cmd-Shift-P`).** Out of scope. A fuzzy-finder over actions is a separate UX surface and would require its own selection model and search index.
- **Touch Bar support.** Out of scope. The macOS-14 baseline still supports Touch Bar but we have no current target audience for it; deferred indefinitely.
- **Services menu integration.** Out of scope. Exposing per-task actions as `NSServices` would require pasteboard contracts and is not in the prototype's scope.
- **Help-menu search.** Out of scope. macOS auto-populates Help → Search to find menu items by name; no extra work needed.
- **Right-click / context menus on rows.** Out of scope for item 4 but a clean follow-up: the existing `availableDetailActions` predicate plus the new `TaskDashboardCommand` cases give us a one-line `.contextMenu { ... }` builder per row in a future checkpoint.
- **Keyboard-shortcut-binding tests.** Explicitly not in scope per §6.3; SwiftUI's `.keyboardShortcut(...)` is not introspectable from `body`. Manual smoke (§7) plus visual source review covers the bindings until a SwiftUI/XCUITest target is introduced.
- **Shortcut collisions with macOS system shortcuts.** Mitigated by the conservative bindings in §3.2 and the analysis in §3.3. If a real-world collision surfaces (for example, a user's screen-reader or third-party app rebinds `Cmd-Opt-R`), the per-row `keyboardShortcut(...)` modifier in `Sources/AgendumMac/AgendumMacApp.swift` is the single point of change.
- **Shortcut collisions with `TextField` input.** Menu key equivalents are matched ahead of the responder chain, so a bound menu shortcut wins over a focused TextField's editing-keystroke handling whenever the menu item is enabled. We mitigate this by (a) avoiding bare backspace bindings — Remove uses `Cmd-Shift-Backspace` per §3.3 — and (b) gating Task-menu items with `.disabled(!availability(on:))` so per-task shortcuts only consume keystrokes when a task is actually selected. With no task selected (the common case when a TextField has focus on, e.g., the New Task sheet's title field), the menu binding is inert and the TextField receives the keystroke normally. If a future shortcut is added that overlaps with a default text-editing combination, the same `.disabled(...)` plus avoidance-of-default-edit-bindings discipline applies.
- **`Cmd-Shift-Backspace` semantic stretch.** The macOS convention for "delete the selected thing" lives at `Cmd-Backspace` (Finder's Move to Trash); we add `Shift` to avoid menu-vs-TextField-edit-keystroke collisions (see §3.3). The trade-off is that we move one step away from Finder's exact idiom, and our binding triggers `removeTask` which actually deletes the task from the agendum store rather than soft-deleting to a trash. We accept the stretch because (a) "remove from list" is the user's mental model for the Remove action, (b) the per-task action's existing `taskActionErrors` plumbing surfaces a recoverable error if the user fires it accidentally, and (c) a confirmation prompt is out of scope (would belong in the per-action remove flow, not in the menu wiring).
- **Multi-window support is out of scope.** The current command surface routes to a single App-level `@StateObject backendStatus`; multi-window would require either per-window models or `FocusedValue`/`focusedSceneValue` plumbing so that `.commands { ... }` can target the focused window's model, neither of which is in this item. The prototype is single-window in practice today.
- **Selection mirror staleness.** If `selectedTaskID` becomes stale (the SwiftUI `selectedTask` updates after the model's `tasks` already mutates underneath, e.g. a `refresh()` removes a task), `perTaskAvailable(...)` (§4.3) returns false because `tasks.first(where: { $0.id == id })` returns nil. The menu item disables itself, the keystroke is ignored, and the next selection change re-syncs. No torn state visible to the user.
- **`isLoading` race during menu invocation.** A user firing `Cmd-Opt-R` (Mark Reviewed) right as `Cmd-R` (Refresh) starts a reload could enqueue two operations. Both flow through the same `@MainActor` discipline as the toolbar buttons (which have the same race window today via mouse clicks). The model's existing `isLoading` toggle and serialization handle it; menu items disable while `isLoading` for refresh/sync/new-task, and per-task actions accept the brief overlap as the existing per-task-button surface does.

## 9. Resolved open questions

All three open questions raised during the design phase have been resolved through reviewer concurrence and revision; recorded here for traceability.

1. **`Cmd-Shift-S` for Sync Now (vs reverting to `Cmd-R`).** Resolved: keep `Cmd-Shift-S`. Reviewer concurred. The existing `Cmd-R` binding for Sync Now (`AgendumMacApp.swift:20`) violated macOS convention (every other "reload" UI uses `Cmd-R`); item 4 corrects this and frees `Cmd-R` for Refresh.
2. **Remove shortcut (`Cmd-Backspace` vs `Cmd-Shift-Backspace` vs no shortcut).** Resolved: bind to `Cmd-Shift-Backspace`. Original recommendation was `Cmd-Backspace` (Finder idiom); reviewer flagged that menu key equivalents are matched ahead of the responder chain, so `Cmd-Backspace` would intercept a focused TextField's "delete to start of line" editing operation. Adding `Shift` eliminates that collision class entirely while keeping a memorable two-key gesture; see §3.3 and §8.
3. **Selection-seam direction (push vs pull).** Resolved: keep the one-way push (SwiftUI `@State` is the source of truth; the model is a mirror written via `setSelectedTaskID(_:)`). Reviewer concurred. The alternative (model owns selection, SwiftUI binds `List(selection:)` to a `Binding(get:set:)` over `selectedTaskID`) inverts ownership and increases the blast radius if other views need to set selection. Prototype scope favours the lighter push-bridge.

### Self-review (five-lens) pass-throughs

- **Correctness.** Every menu command routes to an existing `BackendStatusModel` method; no new business logic enters the model. The selection seam is one published var plus one setter; the SwiftUI side already tracks selection. Availability composes two existing predicates (`isLoading`, `availableDetailActions`).
- **Scope discipline.** Surface area is two source files and one test file. No helper changes. No bridge contract changes. No new SwiftPM products. No new entitlements. Matches `docs/orchestration-plan.md` §Branch and PR Discipline.
- **Missing risks.** Added §8 entries for TextField focus interactions, the `Cmd-Shift-Backspace` semantic stretch, selection mirror staleness, and the `isLoading` race during menu invocation after first-pass review surfaced them.
- **Test strength.** §6.2 covers the brief's required cases (each command invokes the right method, no-op when no selection, targets the selected task, selection bridge propagates, `availableDetailActions` honored, existing Sync Now test passes) plus guard tests for default selection state, named-slot exposure, and the `newTask` no-op contract.
- **Consistency with items 1-3.** Same anchored-claim style (file paths + line numbers). Same SwiftUI-coverage-gap call-out (here phrased as keyboard-shortcut-binding tests not in scope, §6.3 / §8). Same validation-gate enumeration delegated to `docs/orchestration-plan.md` §Validation Gates. The §1-§8 layout matches items 1-3; §9 ("Resolved open questions") is a new trailing section to record the open-question resolution that closed the design phase.
