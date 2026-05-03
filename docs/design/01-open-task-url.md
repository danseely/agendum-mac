# Item 1 Design: Open Task URL Action

Status: design draft, awaiting build phase.
Branch: `codex/item-1-open-task-url` (branched from `feature/mac-prototype` at `12cf468`).
Scope reference: `docs/orchestration-plan.md` §Items, item 1.

## 1. Goal

After this lands, a user viewing a task in the detail pane can press an "Open" action and have the task's canonical URL (`AgendumTask.ghUrl`, surfaced as `TaskItem.url`) open in the user's default browser. Tasks without a URL (manual tasks, or any task whose backend payload omits `ghUrl`) do not show or expose the action. URL opening is routed through `BackendStatusModel` so its side effect (`NSWorkspace.shared.open`) is injected via a test seam, and an open failure surfaces as a per-task error using the existing `taskActionErrors` plumbing introduced in PR #12.

The current SwiftUI `TaskDetail` already has an "Open in Browser" button that calls `@Environment(\.openURL)` directly (`Sources/AgendumMac/AgendumMacApp.swift` lines 319-325). Item 1 replaces that direct call with a workflow-mediated path so the behavior is testable end-to-end and gains structured error reporting, matching the conventions established by `markSeen`/`markReviewed`/etc.

## 2. Surface area

Files this implementation will touch:

- `Sources/AgendumMacWorkflow/TaskWorkflowModel.swift` — add a `URLOpening` seam, an `openTaskURL(id:)` action on `BackendStatusModel`, and an `openURL` initializer parameter. `TaskItem.availableDetailActions` already includes `.openBrowser` when `url != nil` (lines 50-53); no change is needed there.
- `Sources/AgendumMac/AgendumMacApp.swift` — replace the existing `Open in Browser` button body (lines 319-325) so it routes through `backendStatus.openTaskURL(id:)` instead of `@Environment(\.openURL)`. Wire the per-task `actionError` rendering already present at lines 376-391 to cover this action's failures (no view-shape change; the same `actionError: PresentedError?` already drives the error caption). Add an accessibility identifier to the button.
- `Tests/AgendumMacWorkflowTests/TaskWorkflowModelTests.swift` — extend the existing `FakeBackend`-style pattern with a lock-protected `RecordingURLOpener` helper (see §5.1) and add tests covering availability, the success path, the failure path (open returns false), error clearing semantics on subsequent success/refresh/workspace-switch, and the no-URL guard.

No changes expected to:

- `Sources/AgendumMacCore/BackendClient.swift` (the `AgendumTask.ghUrl` field already exists, line 36).
- `Backend/agendum_backend/helper.py` or any Python tests (URL opening is Mac-app-owned per `docs/backend-contract.md` §Ownership Rules).
- `Package.swift` (the `AgendumMacWorkflow` target already exists; we will not add a new product). `AgendumMacWorkflow` is consumed only by the macOS-only `AgendumMac` executable, so `TaskWorkflowModel.swift` will `import AppKit` directly without an `#if canImport(AppKit)` guard.

## 3. Workflow target changes

All additions live in `Sources/AgendumMacWorkflow/TaskWorkflowModel.swift`.

### 3.1 `URLOpening` seam

Mirroring the existing `now: () -> Date` and `sleep: (UInt64) async throws -> Void` seams on `BackendStatusModel.init` (lines 198, 210-211), introduce a typealias and a default that wraps `NSWorkspace.shared.open`:

```swift
public typealias URLOpening = @Sendable (URL) -> Bool
```

The default value is provided through a static helper so the dependency on `AppKit` is centralized:

```swift
public extension BackendStatusModel {
    static var defaultURLOpener: URLOpening {
        { url in NSWorkspace.shared.open(url) }
    }
}
```

Rationale: `AgendumMacWorkflow` is macOS-only in practice (consumed only by `AgendumMac`), so `TaskWorkflowModel.swift` will `import AppKit` directly. No platform guard is needed; matching the existing locale/clock-seam style for default values.

### 3.2 `BackendStatusModel.init` parameter

Extend the designated initializer (line 206) with one parameter, defaulted, so existing call sites (the public `convenience init()` and tests) compile unchanged:

```swift
init(
    client: any AgendumBackendServicing,
    syncPollIntervalNanoseconds: UInt64 = 500_000_000,
    maxSyncPollAttempts: Int = 120,
    sleep: @escaping @Sendable (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) },
    now: @escaping @Sendable () -> Date = Date.init,
    openURL: @escaping URLOpening = BackendStatusModel.defaultURLOpener,
    locale: Locale = .autoupdatingCurrent
)
```

Store as `private let openURL: URLOpening`. The `convenience init()` (line 202) delegates with the default opener. Production code in `AgendumMacApp` keeps using the convenience init.

### 3.3 `openTaskURL(id:)` action

Add a new `@MainActor` method on `BackendStatusModel` that follows the existing `performTaskAction(taskID:)` shape (lines 390-402) but calls the synchronous opener instead of an async backend method, and reports failure via `taskActionErrors` so the UI surface is identical to other per-task errors:

```swift
public func openTaskURL(id: TaskItem.ID) async {
    guard let task = tasks.first(where: { $0.id == id }) else {
        // Unknown task ID: log and return without mutating taskActionErrors.
        // No view can read or clear a stale entry under an id that does not
        // correspond to a visible task, so writing one would leak state.
        return
    }
    guard let url = task.url else {
        taskActionErrors[id] = PresentedError(
            message: "This task has no URL to open.",
            recovery: "Manual tasks have no link; remove them or add a URL upstream.",
            code: "client.taskHasNoURL"
        )
        return
    }
    let opened = openURL(url)
    if opened {
        taskActionErrors.removeValue(forKey: id)
    } else {
        taskActionErrors[id] = PresentedError(
            message: "Could not open the task URL in a browser.",
            recovery: "Check that a default browser is set, then try again.",
            code: "client.urlOpenFailed"
        )
    }
}
```

Notes:
- `async` keeps the call site uniform with the other detail actions in `TaskDetail` (every other `Task { await ... }` block).
- The no-URL branch should be unreachable from the UI because `availableDetailActions` already gates the button on `url != nil`, but treating it defensively keeps the state-clearing rules monotone if the action is ever exposed without a guard.
- The unknown-task-ID branch is also UI-unreachable (the button is rendered from a `task` already in `tasks`); it returns silently rather than recording an error under a phantom id, since no view will ever read or clear `taskActionErrors[id]` for an id that is not present in the task list.
- This action does not mutate `isLoading`. The opener is fast and synchronous; following the per-task-action convention of toggling `isLoading` would briefly disable refresh/sync, which is unnecessary and noisy. This matches the principle that the existing `Open in Browser` button does not currently set `.disabled(isLoading)` (line 319-325).
- Successful open clears the affected task's prior error, just like the other per-task actions do at line 397.

### 3.4 Composition with `availableDetailActions`

No change. `TaskItem.availableDetailActions` already adds `.openBrowser` iff `url != nil` (lines 51-53), and `.openBrowser` is already in the `TaskDetailAction` enum (line 89). The existing detail-actions test on line 495 (`review.availableDetailActions == [.openBrowser, .markSeen, .markReviewed, .remove]`) and the issue-row test on line 504 (`[.remove]` for a `manual` task with `url: nil`) lock this behavior in.

### 3.5 Refresh / workspace-switch error clearing

`refresh()` (line 287) and `selectWorkspace(...)` (line 312) already clear `taskActionErrors` to `[:]`. Since `openTaskURL(id:)` writes into the same map, these existing flows clear URL-open errors automatically; no new code is required. We will assert this in tests rather than add new clearing.

## 4. SwiftUI changes

All in `Sources/AgendumMac/AgendumMacApp.swift`.

### 4.1 `TaskDetail` props

Add one new closure to `TaskDetail` (lines 282-294) so the view stays a thin shell over the model:

```swift
let openInBrowser: () async -> Void
```

### 4.2 Button replacement

Replace lines 319-325:

```swift
if task.availableDetailActions.contains(.openBrowser) {
    Button("Open in Browser") {
        Task {
            await openInBrowser()
        }
    }
    .accessibilityIdentifier("task-action-open-browser")
}
```

Notes:
- Intentionally no `.disabled(isLoading)`. The pre-existing `Open in Browser` button does not have it, and the workflow method does not toggle `isLoading`; adding the modifier would expand scope beyond a strict like-for-like replacement of the current button behavior.
- Identifier `task-action-open-browser` matches the existing convention (see `task-action-error`, `sync-status-state`, etc., listed in `docs/handoff.md` PR #13 changed-files block).
- Removing the `@Environment(\.openURL) private var openURL` stored property (line 283) is OK; it has no other call sites in `TaskDetail`.

### 4.3 Call-site wiring

Update the `TaskDetail(...)` constructor in `TaskDashboardView` (lines 105-136) to pass:

```swift
openInBrowser: {
    await backendStatus.openTaskURL(id: task.id)
},
```

No `selectedTask = nil` reset on success: opening a URL does not navigate the app away from the task, unlike `markReviewed`/`markDone`/`remove` (lines 113-134). The user should remain on the detail pane after opening.

### 4.4 Error surfacing

The existing `actionError: PresentedError?` parameter (line 287) and the caption block at lines 376-391 already render any value from `backendStatus.errorForTask(id: task.id)`. Because `openTaskURL` writes into the same `taskActionErrors` map, no new view code is required to surface open-URL failures.

## 5. Test plan

All in `Tests/AgendumMacWorkflowTests/TaskWorkflowModelTests.swift`. Builds on the existing `FakeBackend` actor pattern and the `task(...)` helper (line 753) which already supports an optional `url` argument.

### 5.1 Test infrastructure

Add a `RecordingURLOpener` test helper as a lock-protected `@unchecked Sendable` class in the test file's private helpers. The `URLOpening` typealias is synchronous (`@Sendable (URL) -> Bool`) because the production opener (`NSWorkspace.shared.open`) is synchronous; an actor-based fake would force the seam to be `async` and is therefore not used here. Concrete signature:

```swift
final class RecordingURLOpener: @unchecked Sendable {
    private let lock = NSLock()
    private var _opened: [URL] = []
    private var _nextResult: Bool = true
    var opened: [URL] {
        lock.lock(); defer { lock.unlock() }
        return _opened
    }
    func setNextResult(_ value: Bool) {
        lock.lock(); defer { lock.unlock() }
        _nextResult = value
    }
    func open(_ url: URL) -> Bool {
        lock.lock(); defer { lock.unlock() }
        _opened.append(url)
        return _nextResult
    }
}
```

Pass it into the model with `openURL: { [opener] url in opener.open(url) }`. `@unchecked Sendable` is acceptable here because all access is lock-protected; this matches Swift 6 sendability rules without forcing the production seam to become async.

### 5.1.1 SwiftUI coverage gap

The workflow-model tests in §5.2 are sufficient for the model layer (button-state availability, opener invocation, success/failure error semantics, no-op guards, and refresh/workspace-switch clearing). They do not exercise the SwiftUI button-wiring path — i.e. that the rendered button with accessibility identifier `task-action-open-browser` actually invokes `backendStatus.openTaskURL(id:)`. That path is currently covered only by the manual `swift run AgendumMac` smoke described in §6, matching the project's existing testing posture for SwiftUI-layer changes (no SwiftUI test target exists today). Introducing a new SwiftUI test target is out of scope for item 1 and is a candidate for a future testing-infrastructure checkpoint.

### 5.2 New / modified tests (one-line intents)

1. `testAvailableDetailActionsIncludesOpenBrowserWhenURLPresent` — the existing detail-actions test at line 487 already asserts `.openBrowser` membership for a review-source task with a URL (line 495) and `.openBrowser` absence for a manual-no-url task (line 504), so this case is already covered. The build phase should leave that test untouched and only add a single explicit assertion in the new `testOpenTaskURLNoOpsWhenTaskHasNoURL` (#5) that `task.availableDetailActions.contains(.openBrowser) == false` when `url` is nil, to keep the no-URL gate self-documenting alongside the model behavior.
2. `testOpenTaskURLInvokesOpenerWithTaskURL` — populate `tasks` via refresh, call `openTaskURL(id:)` for a task whose `url` is `https://example.com/issue/42`, assert the `RecordingURLOpener.opened` array equals `[URL(string: "https://example.com/issue/42")!]` and that no error is recorded.
3. `testOpenTaskURLClearsExistingPerTaskError` — preload `taskActionErrors[17]` by failing a prior `markDone` (existing pattern at lines 181-196), then `openTaskURL(id: 17)` and assert `errorForTask(id: 17)` is nil and global `errorMessage` is nil.
4. `testOpenTaskURLFailureRecordsPerTaskError` — set `RecordingURLOpener.nextResult = false`, call `openTaskURL(id:)`, assert `errorForTask(id: 17)?.code == "client.urlOpenFailed"`, `errorMessage` is nil, tasks unchanged, and `opened` array shows the URL was attempted exactly once.
5. `testOpenTaskURLNoOpsWhenTaskHasNoURL` — for a `manual` task with `url: nil`, call `openTaskURL(id:)`, assert opener was never invoked (`opened.isEmpty`) and `errorForTask(id:)?.code == "client.taskHasNoURL"`. (Defensive coverage of the guard; the UI gate prevents this path in production but the test pins the model contract.)
6. `testOpenTaskURLNoOpsForUnknownTaskID` — call `openTaskURL(id: 999)` against an empty `tasks`; assert the opener was never invoked (`opener.opened.isEmpty`), `taskActionErrors[999]` is `nil`, and `taskActionErrors` is unchanged from its prior state. Pins the §3.3 contract that an unknown task ID returns silently rather than recording a phantom error that no view can read or clear.
7. `testOpenTaskURLDoesNotChangeIsLoading` — assert `isLoading` is false before and after `openTaskURL(id:)` (verifies the deliberate decision in §3.3 not to toggle the loading flag).
8. `testRefreshClearsOpenTaskURLError` — populate an open-URL error, run `refresh()` successfully, assert `taskActionErrors` is `[:]`. Re-uses the existing `testRefreshClearsTaskActionErrors` pattern (already present, see PR #12 entry in `docs/handoff.md`); add an explicit URL-failure preload step.
9. `testSelectWorkspaceClearsOpenTaskURLError` — populate an open-URL error, run `selectWorkspace(id: "example-org")`, assert `taskActionErrors` is `[:]`. Mirrors `testSelectWorkspaceClearsTaskActionErrors`.
10. `testTaskActionsIncludingOpenURLDoNotInterfereWithEachOther` — populate a `markDone` failure on task A, then call `openTaskURL(id:)` on task B, assert task A's error is preserved and task B's slot is empty (open succeeded). Mirrors `testTaskActionFailureOnOneTaskDoesNotClearAnotherTasksError`.

Tests #1, #2, #4, and #8 are the minimum required by the orchestration brief ("action available iff URL present, action disabled/absent when nil, opening invokes the seam exactly once, opening with failing seam surfaces a per-task error, success clears prior error, action does not interfere with refresh/workspace-switch error clearing"). #3, #5, #6, #7, #9, #10 add adjacent coverage at low test-cost using existing fakes.

### 5.3 Test conventions

- Use `XCTAssertEqual(opener.opened.map(\.absoluteString), ["https://example.com/issue/42"])` to compare URLs robustly.
- Reuse `task(id:title:source:status:url:seen:)` (line 753); pass `url: "https://example.com/..."` for URL-bearing fixtures.
- Reuse `immediateSleep` (line 667) for any test that flows through `refresh()`/`forceSync()` so the test stays deterministic.
- Backend protocol (`AgendumBackendServicing`) is unchanged — no `FakeBackend` additions required because URL opening does not cross the helper boundary.

## 6. Validation

Per `docs/testing.md` and the validation gates listed in `docs/orchestration-plan.md` §Validation Gates, the build phase must keep all of the following green:

- `swift build` passes.
- `swift test --enable-code-coverage` passes; expect `AgendumMacWorkflowTests` test count to grow by ~7-10 (one extension to `testAvailableDetailActions...` plus the new tests in §5.2 that are not already covered by existing tests). `AgendumMacCoreTests` count is unchanged.
- `/opt/homebrew/bin/python3 -m unittest discover -s Tests` passes (Python helper unchanged; expect identical test count to the post-PR-#16 baseline of 48).
- `/opt/homebrew/bin/python3 Scripts/python_coverage.py` passes (no helper changes; coverage stays at 464/505 lines, 91.9%).
- `git diff --check` passes.
- `swift run AgendumMac` smoke-launches without immediate crash, and a manual click-through confirms a real task URL opens in the default browser. (Item 1 is service-shaped enough to warrant a real launch smoke; the open-URL side effect is the only behavior that cannot be fully covered by SwiftPM tests.)

No helper protocol surface is touched, so no subprocess JSONL test additions are required (per `docs/orchestration-plan.md` §Validation Gates last bullet).

## 7. Risks / out-of-scope

- **Focus model.** Out of scope for item 1. Item 4 (`codex/item-4-shortcuts-menus`) covers keyboard-only navigation of detail-pane actions; item 1 only adds a button and a model method.
- **Sandbox / Mac App Store interactions.** Non-sandboxed dev build path is verified by the §6 smoke. Sandboxed-bundle behavior is deferred to the future packaging-decision checkpoint (`docs/packaging.md`); this design makes no claims about it. All seven still-deferred packaging decisions in `docs/packaging.md` remain deferred; this checkpoint does not preempt any of them.
- **Malformed `ghUrl` strings.** `TaskItem.url` is built via `URL(string:)`, so a malformed backend URL produces `url == nil` and `availableDetailActions` silently omits `.openBrowser`. We accept this for item 1: the bridge-protocol error path is heavyweight for a developer-facing edge case in the prototype phase. Future checkpoint: if real users encounter this in practice, surface a "URL malformed" diagnostic (e.g. via the same `taskActionErrors` channel or a workflow-level warning) rather than silently dropping the action.
- **Ambiguous `NSWorkspace.shared.open` Bool.** The API returns `false` indistinguishably for "no handler registered" and "handler launch failed" (and other AppKit-internal failures). The build phase will not attempt to disambiguate; the user-visible recovery copy in §3.3 ("Check that a default browser is set, then try again.") covers both cases adequately.
- **Telemetry on URL opens.** Out of scope. We will not record analytics events for URL opens.
- **Copy-link variant.** Out of scope. A right-click "Copy Link" or `Cmd-C` variant is a reasonable follow-up; if surfaced, it should reuse the same `URLOpening`-style seam (or a parallel `URLPasteboarding` seam) and the same per-task error pattern.
- **`NSWorkspace.shared.open(URL)` returning `false`.** This rarely happens in practice (default browser typically registered), but the API does return `Bool` and we honor it. The presented error code `client.urlOpenFailed` is a new, model-only code (not a `BackendClientError`); this is consistent with the existing `client.taskHasNoURL` rationale and with the precedent of `client.unknown`/`client.timeout`/etc. defined in `PresentedError.from(_:)` (lines 136-178).
- **Universal links / non-HTTP URLs.** Backend `ghUrl` is always `https://github.com/...` per the bridge schema (`docs/backend-contract.md` §Shared Types §Task), so we accept whatever `URL.init(string:)` produces and let `NSWorkspace` decide. We do not whitelist schemes.
- **Identifier collision risk.** `task-action-open-browser` is new; existing identifiers (`task-action-error`, `task-action-error-recovery`, `sync-status-state`, etc.) do not conflict.

## 8. Open questions

None. The three questions raised during self-review were resolved by the independent review:

- `RecordingURLOpener` shape: settled on lock-protected `@unchecked Sendable` (see §5.1).
- `#if canImport(AppKit)` guard on `defaultURLOpener`: dropped; `TaskWorkflowModel.swift` imports `AppKit` directly (see §2 and §3.1).
- `.disabled(isLoading)` on the new button: dropped to match the existing `Open in Browser` button's behavior (see §4.2).
