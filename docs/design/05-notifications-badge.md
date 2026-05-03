# Item 5 Design: Notifications + Dock Badge for Sync Results

Status: design draft, awaiting reviewer cycle.
Branch: `codex/item-5-notifications-badge` (branched from `feature/mac-prototype` at `158954c`).
Scope reference: `docs/orchestration-plan.md` §Items, item 5 (the LAST item in the orchestration).

## 1. Goal

After this lands, a user who runs Agendum and triggers a sync (toolbar Sync button, `Cmd-Shift-S` menu, or workspace-switch-driven implicit reload) sees two new ambient surfaces:

1. **A notification banner** posted via `UNUserNotificationCenter` when `BackendStatusModel.forceSync()` finishes — one body for the success path (e.g. "Sync complete. 4 attention items.") and one body for the failure path (e.g. "Sync failed: GitHub auth needed."). The notification only fires when the user has granted notification authorization; if not authorized, the seam silently no-ops (no exceptions surfaced to UI).
2. **A dock badge** on the macOS Dock tile that reflects `BackendStatusModel.hasAttentionItems` (`Sources/AgendumMacWorkflow/TaskWorkflowModel.swift:404-406`). When the count is greater than zero the dock tile shows the integer; when zero the badge clears (the macOS convention is to nil-out `dockTile.badgeLabel` rather than show "0").

The Settings scene gains a small section that shows the current notification authorization state (`Allowed` / `Denied` / `Not requested`) and an `Enable notifications` button that calls `UNUserNotificationCenter.current().requestAuthorization(options:)` when the state is `Not requested`. When the state is `Denied`, the button is replaced with a caption pointing the user at System Settings → Notifications → Agendum (we cannot programmatically open that pane reliably across macOS versions; a static caption is enough for the prototype).

The current code base posts no notifications and never writes to `NSApplication.shared.dockTile`. The `hasAttentionItems` computed property (introduced in PR #13) is rendered only as a small orange badge in the sidebar status panel (`Sources/AgendumMac/AgendumMacApp.swift:438-442`); item 5 surfaces the same signal in the system-wide dock badge so the user notices it without having Agendum frontmost.

## 2. Surface area

Files this implementation will touch:

- `Sources/AgendumMacWorkflow/TaskWorkflowModel.swift`
  - Add a `Notifying` typealias at file scope alongside `URLOpening` (line 6) and `Pasteboarding` (line 7).
  - Add a `BadgeSetting` typealias at file scope alongside the other seam typealiases.
  - Add a small `NotificationContent` struct (title, body, identifier) carried by the `Notifying` closure.
  - Add `notifier: Notifying` and `setBadge: BadgeSetting` initializer parameters on `BackendStatusModel.init` (line 336), defaulted to `BackendStatusModel.defaultNotifier` and `BackendStatusModel.defaultBadgeSetter` so existing call sites continue to compile without change.
  - Add `public static var defaultNotifier: Notifying` inside the existing `public extension BackendStatusModel` block at line 616 (alongside `defaultURLOpener` and `defaultPasteboard`). The default wraps a `UNMutableNotificationContent` and posts a `UNNotificationRequest` via `UNUserNotificationCenter.current().add(_:)`. It checks `getNotificationSettings()` and returns silently when `authorizationStatus != .authorized` (and `!= .provisional`) — the seam does its own gating so the workflow logic doesn't need to know about authorization.
  - Add `public static var defaultBadgeSetter: BadgeSetting` in the same extension. The default writes to `NSApplication.shared.dockTile.badgeLabel` on the main actor — `nil` for count == 0, `String(count)` otherwise — and calls `display()` after the write so the change is committed.
  - Append a notification post to the success and failure paths of `BackendStatusModel.forceSync()` (lines 464-476). On success build a `NotificationContent` from `sync.state` / `sync.changes` / `hasAttentionItems`; on failure build one from the structured `error: PresentedError`. The notifier is invoked with `await notifier(...)` (no `try`) — the `Notifying` typealias is non-throwing, so the seam owns any internal swallowing of `UNUserNotificationCenter` errors and the workflow caller never sees them.
  - Add `public func setBadgeForAttentionCount()` — a one-liner `@MainActor` method that reads `attentionItemCount` (see below) and calls `setBadge(count)`. The App layer's `.onChange(of: backendStatus.hasAttentionItems)` calls this method.
  - Add a `public var attentionItemCount: Int` computed property that returns `sync?.attentionItemsCount ?? 0` if the helper response carries an explicit count, otherwise falls back to `hasAttentionItems ? 1 : 0`. **OQ1 below covers the contract question.** If the backend payload only exposes the boolean `hasAttentionItems` (the Swift-side accessor at line 404 reads `sync?.hasAttentionItems`), the integer is `0` or `1`. If a follow-up extends `SyncStatus` with an explicit count, this accessor adapts without churning the App-layer wiring.
- `Sources/AgendumMac/AgendumMacApp.swift`
  - Add a `.onChange(of: backendStatus.hasAttentionItems)` modifier on the `WindowGroup`'s top-level view (or on `TaskDashboardView.body` alongside the existing `.onChange(of: selectedTask)` at lines 253-255) that calls `backendStatus.setBadgeForAttentionCount()`. Co-locating with the existing `.onChange` minimises App-layer diff.
  - Add a small `Section("Notifications")` to `SettingsView` (lines 691-783) that displays the current authorization state and exposes an `Enable notifications` button when the state is `Not requested`. The state is read via `@State private var notificationAuthorizationStatus: UNAuthorizationStatus?` populated in a `.task` block that calls `UNUserNotificationCenter.current().notificationSettings()`. The button calls `requestAuthorization(options: [.alert, .badge, .sound])` and re-reads settings on completion.
  - Identifiers: `settings-notifications-status`, `settings-action-enable-notifications`.
  - Import `UserNotifications` (and `AppKit` is already imported transitively via `AgendumMacWorkflow`).
- `Tests/AgendumMacWorkflowTests/TaskWorkflowModelTests.swift`
  - Add `RecordingNotifier` and `RecordingBadgeSetter` test helpers — both lock-protected `@unchecked Sendable` recorders, mirroring the `RecordingURLOpener` and `RecordingPasteboard` patterns established by item 1's design (`docs/design/01-open-task-url.md` §5.1) and item 3's design (`docs/design/03-settings-auth-repair.md` §6.4 / §5.4).
  - Add tests covering: success-path notification post, failure-path notification post, suppressed-notification path (the seam returns silently), badge-on-attention-items-change, badge-clears-when-count-is-zero, badge-set-on-explicit-call, and the `attentionItemCount` accessor behavior.

No changes expected to:

- `Backend/agendum_backend/helper.py` or any Python tests. The helper protocol is untouched; the `hasAttentionItems` boolean already flows through `sync.status` / `sync.force` responses. **If OQ1 below resolves toward an explicit integer count,** that becomes a separate follow-up item rather than getting absorbed into item 5.
- `Sources/AgendumMacCore/BackendClient.swift`. No new client methods. `SyncStatus` already exposes `hasAttentionItems`.
- `Package.swift`. No new targets or products. `AgendumMacWorkflow` already imports `AppKit`; we additionally `import UserNotifications` in `TaskWorkflowModel.swift` (`UserNotifications` is part of the macOS SDK and available unconditionally on macOS 10.14+; our `LSMinimumSystemVersion` is 14.0).
- `docs/backend-contract.md`. No bridge surface changes.
- `Tests/test_backend_helper.py`, `Tests/test_backend_helper_process.py`, `Tests/AgendumMacCoreTests/BackendClientTests.swift`. No protocol or client changes.
- The `Sources/AgendumMac/Info.plist.template`. Notification entitlements for `UNUserNotificationCenter` do not require an Info.plist key — `NSUserNotificationsUsageDescription` is a legacy `NSUserNotification` requirement; the modern `UserNotifications` framework only needs runtime authorization. Sandbox / hardened-runtime / MAS interactions remain deferred per `docs/packaging.md`; see §7.

## 3. Workflow target changes

All additions in `Sources/AgendumMacWorkflow/TaskWorkflowModel.swift`.

### 3.1 `Notifying` and `BadgeSetting` seams

Add to the existing typealias block at file scope (after lines 6-7):

```swift
public typealias Notifying = @Sendable (NotificationContent) async -> Void
// non-throwing; the closure may internally `try?` UNUserNotificationCenter errors but does not propagate them.
public typealias BadgeSetting = @Sendable (Int) -> Void

public struct NotificationContent: Equatable, Sendable {
    public let identifier: String
    public let title: String
    public let body: String

    public init(identifier: String, title: String, body: String) {
        self.identifier = identifier
        self.title = title
        self.body = body
    }
}
```

Notes:

- `Notifying` is `async` (not `async throws`) because the seam itself decides whether to suppress posts based on authorization state, and a thrown error from the inner `UNUserNotificationCenter.add(_:)` should not be observable to the workflow caller. Suppressing-vs-posting is a concern the seam owns, not the model.
- `BadgeSetting` is synchronous because writing `dockTile.badgeLabel` is a fast, main-thread-safe property assignment. Wrapping it in `async` would add ceremony without value.
- `NotificationContent.identifier` is included so multiple sync notifications coalesce predictably (using the same identifier across sync events causes macOS to replace the existing banner rather than stacking N copies). The default identifier is `"agendum.sync.completed"`; both success and failure paths use it on purpose.
- The struct is `Equatable` so `RecordingNotifier` tests can use `XCTAssertEqual` to assert recorded payloads.

### 3.2 Default notifier

Add to the `public extension BackendStatusModel` block at line 616 (alongside `defaultURLOpener` and `defaultPasteboard`):

```swift
static var defaultNotifier: Notifying {
    { content in
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional else {
            return
        }
        let mutable = UNMutableNotificationContent()
        mutable.title = content.title
        mutable.body = content.body
        let request = UNNotificationRequest(
            identifier: content.identifier,
            content: mutable,
            trigger: nil
        )
        try? await center.add(request)
    }
}
```

Notes:

- The seam silently no-ops when authorization is `.denied` or `.notDetermined`. We deliberately do NOT call `requestAuthorization` from inside the workflow target — that lives in the App layer (§4) so the request only happens with a clear user-driven UI affordance.
- `try?` swallows errors from `add(_:)`. The notification system can refuse a post for various reasons (badly formed identifier, system-wide DND, etc.); none of those should affect the sync flow.
- `.provisional` is included to support quiet-delivery notifications — a future affordance — without forcing a code change. For the prototype the user will only ever land on `.authorized` (because we request `[.alert, .badge, .sound]`) or `.denied`/`.notDetermined`.

### 3.3 Default badge setter

```swift
static var defaultBadgeSetter: BadgeSetting {
    { count in
        MainActor.assumeIsolated {
            let label: String? = count > 0 ? String(count) : nil
            NSApplication.shared.dockTile.badgeLabel = label
            // macOS redraws the dock tile automatically on `badgeLabel`
            // writes from the main actor; `display()` is required only when
            // drawing custom content via `setContentView(_:)`. We are not
            // setting custom content, so it is omitted.
        }
    }
}
```

Notes:

- `MainActor.assumeIsolated` is safe because the App-layer call site (`.onChange(of: ...)` on a SwiftUI body) is already main-actor-bound; the assumption is documentation, not a runtime contract change. If a future caller invokes this from a non-main context, `assumeIsolated` traps in debug builds and we add an `await MainActor.run { ... }` wrapper instead. For item 5 every call site is main-actor, so the trap path is unreachable.
- `count > 0 ? String(count) : nil` enforces the badge-clearing rule (count == 0 ⇒ no badge).
- `dockTile.display()` is intentionally omitted — macOS redraws the dock tile automatically on `badgeLabel` writes from the main actor; `display()` is required only when drawing custom content via `setContentView(_:)`. We are not setting custom content, so it is omitted.

### 3.4 Initializer parameters

Extend the designated initializer at line 336:

```swift
init(
    client: any AgendumBackendServicing,
    syncPollIntervalNanoseconds: UInt64 = 500_000_000,
    maxSyncPollAttempts: Int = 120,
    sleep: @escaping @Sendable (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) },
    now: @escaping @Sendable () -> Date = Date.init,
    openURL: @escaping URLOpening = BackendStatusModel.defaultURLOpener,
    pasteboard: @escaping Pasteboarding = BackendStatusModel.defaultPasteboard,
    notifier: @escaping Notifying = BackendStatusModel.defaultNotifier,
    setBadge: @escaping BadgeSetting = BackendStatusModel.defaultBadgeSetter,
    locale: Locale = .autoupdatingCurrent,
    filters: TaskListFilters = .default
)
```

Stored as `private let notifier: Notifying` and `private let setBadge: BadgeSetting`. The `convenience init()` (line 332) and existing test seams continue to work unchanged because every new parameter has a default.

### 3.5 `forceSync` integration

Replace the body of `forceSync()` at lines 464-476 with:

```swift
public func forceSync() async {
    isLoading = true
    defer { isLoading = false }

    do {
        sync = try await client.forceSync()
        try await pollSyncUntilComplete()
        tasks = try await loadTaskItems()
        self.error = nil
        if sync?.state == "error" {
            // Backend-reported error path: forceSync did not throw, but the
            // resulting SyncStatus carries state == "error". Treat as failure
            // for notification purposes; do NOT clobber self.error here — the
            // existing error-propagation contract from item 3 already handles
            // model-level error surfacing. Route through the shared helper by
            // synthesizing a PresentedError so the failure-body template lives
            // in exactly one place.
            let suffix = sync?.lastError ?? "Unknown error."
            await postSyncCompletedNotification(
                success: false,
                failure: PresentedError(message: suffix)
            )
        } else {
            await postSyncCompletedNotification(success: true, failure: nil)
        }
    } catch {
        let presented = PresentedError.from(error)
        self.error = presented
        await postSyncCompletedNotification(success: false, failure: presented)
    }
}

private func postSyncCompletedNotification(
    success: Bool,
    failure: PresentedError?
) async {
    let body: String
    if success {
        let count = attentionItemCount
        if count > 0 {
            body = "Sync complete. \(count) attention item\(count == 1 ? "" : "s")."
        } else {
            body = "Sync complete."
        }
    } else {
        let suffix = failure?.message ?? "Unknown error."
        body = "Sync failed: \(suffix)"
    }
    await postSyncCompletedNotification(body: body)
}

private func postSyncCompletedNotification(body: String) async {
    // Shared identifier across success and failure shapes so macOS coalesces
    // repeated banners (the user sees the latest, not a stack of N).
    await notifier(NotificationContent(
        identifier: "agendum.sync.completed",
        title: "Agendum",
        body: body
    ))
}
```

Notes:

- The post is the LAST thing `forceSync` does on every terminal path. Test assertions can therefore observe the post deterministically after `await model.forceSync()` returns; no additional polling required.
- Three terminal paths: (a) `client.forceSync()` returns and the resulting `sync?.state` is anything other than `"error"` — post the success body; (b) `client.forceSync()` returns BUT `sync?.state == "error"` — synthesize a `PresentedError(message: sync?.lastError ?? "Unknown error.")` and route through the shared `postSyncCompletedNotification(success:failure:)` helper; (c) `client.forceSync()` throws — route through the same shared helper using `PresentedError.from(error)`. Branches (b) and (c) call the SAME `postSyncCompletedNotification(success:failure:)` helper, so the failure-body template (`"Sync failed: \(suffix)"`) lives in exactly one site. All three share the identifier `"agendum.sync.completed"` so macOS coalesces banners across repeated syncs.
- The (b) branch deliberately does NOT clobber `self.error`. Item 3's error-propagation contract already determines when `self.error` is populated from `sync?.lastError` (see `Sources/AgendumMacWorkflow/TaskWorkflowModel.swift:320` for the `errorMessage` shim that reads `error?.message`). The notification post is an additive surface; it must not interfere with the existing error-state contract. Branch (b) intentionally leaves `self.error` untouched to preserve item-3's contract; the notification is the user-visible signal for backend-reported sync errors. The dashboard error caption stays empty on this branch on purpose — see §7's "Synthesized `PresentedError` on branch (b) is notification-only" bullet for the full rationale.
- Pluralization is computed inline; no `Foundation.NumberFormatter`-style ceremony.
- The shared identifier `"agendum.sync.completed"` ensures repeated syncs replace the previous banner instead of cluttering the user's notification center with N copies.

### 3.6 `setBadgeForAttentionCount` and `attentionItemCount`

```swift
public var attentionItemCount: Int {
    // Today the backend payload exposes a boolean (hasAttentionItems);
    // tomorrow it may carry an explicit integer. The accessor
    // adapts so the SwiftUI .onChange wiring doesn't need to know.
    return hasAttentionItems ? 1 : 0
}

public func setBadgeForAttentionCount() {
    setBadge(attentionItemCount)
}
```

Notes:

- The accessor is intentionally `Int`, not `Bool`, even though today it only ever returns 0 or 1. The integer surface lets the App-layer `.onChange(of: backendStatus.hasAttentionItems)` write a real count to the dock badge, and lets a future contract change (an explicit integer field on `SyncStatus`) flow through without an App-layer diff.
- `setBadgeForAttentionCount()` is callable from the App layer's `.onChange` and from tests. We deliberately do NOT call it from `forceSync` directly: the App layer's `.onChange(of: backendStatus.hasAttentionItems)` already fires whenever a sync settles a new value, and routing badge updates through that single observation point (rather than through both `.onChange` and a `forceSync`-internal call) keeps the badge update path single-writer. **OQ2 below covers an alternate routing.**

### 3.7 Composition with existing flows

- `refresh()` (line 412) is unchanged; it does not post sync notifications because it is an implicit reload, not an explicit user-driven sync.
- `selectWorkspace(...)` (line 437) is unchanged; the implicit reload also does not post a notification. (`hasAttentionItems` may change as a side-effect; the badge `.onChange` fires regardless of which method drove the change.) `.onChange(of: hasAttentionItems)` fires only on value transitions, so concurrent writers (e.g. `selectWorkspace` reload + `forceSync`) converging on the same final value emit at most one badge update.
- Per-task action methods (`markSeen`, `markReviewed`, etc.) are unchanged.
- Authorization state is NOT a model concern. The seam decides whether to actually post; the model just hands content to the seam. This keeps the workflow target free of `UNUserNotificationCenter` knowledge except in the seam's default closure.

## 4. SwiftUI changes

All in `Sources/AgendumMac/AgendumMacApp.swift`.

### 4.1 Badge `.onChange`

Add to `TaskDashboardView.body` after the existing `.onChange(of: selectedTask)` at lines 253-255:

```swift
.onChange(of: backendStatus.hasAttentionItems) { _, _ in
    backendStatus.setBadgeForAttentionCount()
}
.task {
    // Prime on first appear runs alongside the existing
    // `await backendStatus.refresh()` `.task`. SwiftUI does not order
    // multiple `.task` blocks, so the prime typically clears any stale
    // badge value (since `attentionItemCount == 0` until a sync result
    // arrives) and the subsequent `.onChange(of: hasAttentionItems)`
    // repopulates the badge once `refresh()` settles. Net behavior is
    // correct; this `.task` is a cheap cold-start hedge, not a
    // load-bearing populator.
    backendStatus.setBadgeForAttentionCount()
}
```

The existing `.task { await backendStatus.refresh() }` block at lines 250-252 stays as-is — the prime-on-appear `.task` block above is a separate one-line modifier that runs alongside it.

Notes:
- We watch `hasAttentionItems` (Bool) rather than `attentionItemCount` (Int) because today they encode the same information; if `attentionItemCount` later carries a real integer count from the backend, this `.onChange` should be migrated to watch the integer accessor directly. The migration is one line.
- Co-locating with the existing `.onChange(of: selectedTask)` keeps both observers near the body's `.task { ... }`. No alternate view is introduced.

### 4.2 Settings notification section

Inside `SettingsView.body`'s `Form` (around line 738, before the existing actions `Section`), add:

```swift
Section("Notifications") {
    LabeledContent("Status", value: notificationStatusLabel)
        .accessibilityIdentifier("settings-notifications-status")
    if notificationAuthorizationStatus == .notDetermined {
        Button("Enable notifications") {
            Task {
                let granted = (try? await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .badge, .sound])) ?? false
                _ = granted
                await refreshNotificationSettings()
            }
        }
        .accessibilityIdentifier("settings-action-enable-notifications")
    } else if notificationAuthorizationStatus == .denied {
        Text("Open System Settings → Notifications → Agendum to enable notifications.")
            .font(.caption)
            .foregroundColor(.secondary)
            .accessibilityIdentifier("settings-notifications-denied-hint")
    }
}
```

Wire the supporting `@State` and helpers on `SettingsView`:

```swift
@State private var notificationAuthorizationStatus: UNAuthorizationStatus?

private var notificationStatusLabel: String {
    switch notificationAuthorizationStatus {
    case .authorized, .provisional, .ephemeral:
        return "Allowed"
    case .denied:
        return "Denied"
    case .notDetermined:
        return "Not requested"
    case .none:
        return "Loading…"
    @unknown default:
        return "Unknown"
    }
}

private func refreshNotificationSettings() async {
    let settings = await UNUserNotificationCenter.current().notificationSettings()
    notificationAuthorizationStatus = settings.authorizationStatus
}
```

Add to the existing `.task` block at line 769:

```swift
.task {
    await backendStatus.refreshDiagnostics()
    await refreshNotificationSettings()
}
```

Notes:
- We do NOT auto-prompt for authorization on first Settings open. The user clicks `Enable notifications` deliberately. This matches Apple's HIG guidance (don't prompt for system permissions until the user requests the gated feature).
- The `Denied` branch uses a static caption rather than a button that programmatically opens System Settings. macOS's `x-apple.systempreferences:` URL scheme works in some macOS versions but is fragile across the 14.0+ baseline; the caption is reliable.
- Identifiers follow the existing `settings-*` namespace from item 3.

### 4.3 No menu / toolbar changes

We do NOT add a "Toggle notifications" menu item or a dock-badge toggle toolbar control. The Settings pane plus the `.onChange` observer is sufficient.

## 5. Test plan

All in `Tests/AgendumMacWorkflowTests/TaskWorkflowModelTests.swift`. Mirror the lock-protected `@unchecked Sendable` recorder pattern from item 1's design (`docs/design/01-open-task-url.md` §5.1) and item 3's design (`docs/design/03-settings-auth-repair.md` §6.4).

### 5.1 Test infrastructure

Add two new helpers (next to `RecordingURLOpener` / `RecordingPasteboard` from earlier items):

```swift
private final class RecordingNotifier: @unchecked Sendable {
    private let lock = NSLock()
    private var _posted: [NotificationContent] = []
    private let suppressed: Bool

    init(suppressed: Bool = false) { self.suppressed = suppressed }

    var posted: [NotificationContent] {
        lock.lock(); defer { lock.unlock() }
        return _posted
    }

    func record(_ content: NotificationContent) {
        if suppressed { return }
        lock.lock(); defer { lock.unlock() }
        _posted.append(content)
    }
}

private final class RecordingBadgeSetter: @unchecked Sendable {
    private let lock = NSLock()
    private var _values: [Int] = []

    var values: [Int] {
        lock.lock(); defer { lock.unlock() }
        return _values
    }

    func record(_ count: Int) {
        lock.lock(); defer { lock.unlock() }
        _values.append(count)
    }
}
```

`record(_:)` is synchronous; the wrapping `[recorder] in await ...` async closure satisfies the `@Sendable async -> Void` seam shape without forcing actor hops inside the recorder.

Each test wires the recorder via inline `[recorder]` capture at the call site, matching the existing `RecordingURLOpener` / `RecordingPasteboard` shape at `Tests/AgendumMacWorkflowTests/TaskWorkflowModelTests.swift:1419-1454`:

```swift
let notifier = RecordingNotifier()
let badge = RecordingBadgeSetter()
let model = BackendStatusModel(
    client: backend,
    notifier: { [notifier] content in notifier.record(content) },
    setBadge: { [badge] count in badge.record(count) }
)
```

The `suppressed: true` mode on `RecordingNotifier` lets one test exercise the App-layer "user denied notifications" path (the real seam silently returns; the recorder's suppressed mode mirrors that contract without needing real `UNUserNotificationCenter` state).

### 5.2 New tests (one-line intents)

Notification posts:

1. `testForceSyncSuccessPostsCompletionNotification` — fake backend returns a successful `sync.force` followed by `sync.status` with `state == "completed"` and `hasAttentionItems == false`; await `model.forceSync()`; assert `notifier.posted.count == 1`, identifier `"agendum.sync.completed"`, title `"Agendum"`, body contains `"Sync complete."`.
2. `testForceSyncSuccessWithAttentionItemsIncludesCountInBody` — same as #1 but `hasAttentionItems == true`; assert body contains `"1 attention item"` (singular pluralization).
3. `testForceSyncFailurePostsFailureNotification` — fake `forceSync` throws a structured `BackendClientError`; await `model.forceSync()`; assert `notifier.posted.count == 1`, that the body contains `"Sync failed:"`, and that the body contains the presented message via `XCTAssertTrue(body.contains(presented.message))` (substring rather than equality so future copy-edits to the body template don't break the test). ALSO assert that the existing item-3 error-propagation contract is preserved: `XCTAssertEqual(model.error?.message, presented.message)` after `forceSync()` returns. The notification post must be additive — it must NOT clobber or replace the structured `error` surfacing on the model. Coverage extends to backend-reported error states (the `sync?.state == "error"` branch in §3.5): a sibling test `testForceSyncBackendReportedErrorPostsFailureNotification` exercises the throw-free "state == error" path and asserts the body contains `"Sync failed:"` and the value of `sync.lastError`. That sibling test ALSO asserts `XCTAssertNil(model.error)` after `forceSync()` returns (or `XCTAssertEqual(model.error?.message, priorErrorMessage)` if the test seeded an existing error before the call) to pin the intentional `self.error == nil` gap on branch (b) per §3.5.
4. `testForceSyncSuppressedNotifierDoesNotCrashAndPostsNothing` — use `RecordingNotifier(suppressed: true)`; await `model.forceSync()` on the success path; assert `notifier.posted.isEmpty` and `model.error == nil`. ALSO exercise the failure path with the same suppressed recorder: configure the fake to throw a `BackendClientError` on `forceSync`, await `model.forceSync()`, and assert `notifier.posted.isEmpty` (suppressed seam doesn't crash on the failure branch either) AND `model.error != nil` (the structured-error contract still populates `self.error` even when notifications are suppressed). ALSO exercise branch (b) with the same suppressed recorder: configure a fake whose `forceSync` returns `SyncStatus(state: "error", lastError: "...")` without throwing, await `model.forceSync()`, and assert `notifier.posted.isEmpty` AND `model.error == nil` (matching the §3.5 intentional-gap contract from finding 1).
5. `testForceSyncShareSingleNotificationIdentifier` — call `model.forceSync()` twice (both success); assert both posts carry the same identifier `"agendum.sync.completed"` (so macOS coalesces them rather than stacking duplicates).
6. `testForceSyncPostsSuccessBodyForNonErrorStates` — defensive pin on the §3.5 classifier; intent is bidirectional so a polarity flip in the classifier (success vs failure routing) fails at least one assertion in the pair below. Use a `FakeBackend` that returns `sync.state == "idle"` (or another current non-error value used by today's helper) AND that does NOT throw from `forceSync`; await `model.forceSync()`; assert the notification body uses the success template (`body.contains("Sync complete")` AND NOT `body.contains("Sync failed")`). ALSO add an explicit "error direction" assertion (either inline as a second sub-case or folded into the branch-(b) sibling test from #3): with `forceSync` returning `SyncStatus(state: "error", lastError: "boom")` non-throwingly, assert the body contains `"Sync failed:"` AND the value of `sync.lastError` (e.g. `"boom"`). The two directions together pin the bidirectional classifier. If the helper protocol introduces a new failure-shaped state value (e.g. `"degraded"`, `"partial"`), this test must be updated alongside the classifier in `forceSync`.

Badge updates:

7. `testSetBadgeForAttentionCountWritesZeroWhenNoSync` — fresh model, no `sync` populated; call `model.setBadgeForAttentionCount()`; assert `badge.values == [0]`.
8. `testSetBadgeForAttentionCountWritesOneWhenAttentionItemsTrue` — set `sync` via a successful refresh whose response carries `hasAttentionItems == true`; call `model.setBadgeForAttentionCount()`; assert `badge.values.last == 1`.
9. `testSetBadgeForAttentionCountWritesZeroWhenAttentionItemsFalse` — populate `sync` with `hasAttentionItems == false`; call `model.setBadgeForAttentionCount()`; assert `badge.values.last == 0`. Pins the count == 0 contract that the App-layer default seam translates to a nil `badgeLabel`.
10. `testAttentionItemCountAccessorReflectsSyncBoolean` — table-driven over `(hasAttentionItems: Bool, expectedCount: Int)` for `{(true, 1), (false, 0)}`; assert `model.attentionItemCount` matches.
11. `testAttentionItemCountIsZeroWhenSyncIsNil` — fresh model; assert `model.attentionItemCount == 0`. Pins the `?? 0` fallback in the accessor.

Composition:

12. `testForceSyncDoesNotInvokeBadgeSeamDirectly` — await `model.forceSync()` with a fake that flips `hasAttentionItems`; assert `XCTAssertTrue(badge.values.isEmpty)`. Pins the §3.6 contract that `forceSync` does NOT call `setBadge` directly; the App layer's `.onChange` is the only writer. (Use `values.isEmpty` rather than `values.last == nil`; an empty array's `.last` is also `nil` but the empty-check is the contract under test.)
13. `testRefreshDoesNotPostNotification` — call `model.refresh()` (success path); assert `notifier.posted.isEmpty`. Pins the §3.7 contract that implicit refreshes don't notify.
14. `testSelectWorkspaceDoesNotPostNotification` — populate `workspaces`, call `model.selectWorkspace(id:)`; assert `notifier.posted.isEmpty`. Same posture as #13.

Initializer wiring:

15. `testDefaultNotifierAndBadgeSetterAreUsedByConvenienceInit` — instantiate `BackendStatusModel()`; assert (via mirror reflection on private storage, or via a discoverable-as-non-nil sentinel) that the closures are non-nil. *Lighter alternative:* assert that calling `setBadgeForAttentionCount()` on a freshly-constructed model with the default seam does not crash, since the default seam writes to `NSApplication.shared.dockTile.badgeLabel` which is safe in the test process. We adopt the lighter form to avoid reflecting on private storage; the trade-off is that we exercise the `dockTile` write in the unit test runner. If reviewer flags that as test-side-effect leakage, fall back to a structural assertion (the parameter list compiles unchanged). **OQ3 below covers this.**

### 5.3 Tests explicitly NOT in scope

- The `.task`-driven `refreshNotificationSettings()` call in `SettingsView` and the `Enable notifications` button's authorization-request behavior are SwiftUI-layer flows that are not unit-tested here. This matches the existing posture for SwiftUI binding-shaped behavior in items 1-4 (see `docs/design/01-open-task-url.md` §5.1.1, `docs/design/02-task-list-filtering.md` §5.4, `docs/design/03-settings-auth-repair.md` §6.5, `docs/design/04-shortcuts-menus.md` §6.3). Manual smoke (§6) covers it.
- We do not test `UNUserNotificationCenter` integration. The default `defaultNotifier` closure is exercised via §5.2 #14's lightest-form assertion (or its structural fallback); the actual notification banner is verified by the §6 manual smoke step.
- We do not test that `NSApplication.shared.dockTile.badgeLabel` ends up with the right string in the running app. The seam abstraction is what the tests assert; the seam-to-dock-tile binding is one line of `defaultBadgeSetter` and is verified manually.

### 5.4 Test conventions

- Use `await model.forceSync()` then `let posted = notifier.posted` to read the recorder; the post is sequenced inside `forceSync` via `await notifier(...)` so the read after the await is deterministic.
- For success-path tests, populate the fake's `forceSync()` and `syncStatus()` returns by calling the existing private test helper at `Tests/AgendumMacWorkflowTests/TaskWorkflowModelTests.swift:1729` — `sync(state:changes:lastError:lastSyncAt:hasAttentionItems:)`. `SyncStatus` has no public memberwise initializer; the helper decodes from a JSON string and is what every existing test in the file uses (e.g. `sync(state: "idle", hasAttentionItems: true)`). Reuse it as-is rather than introducing a new construction shape.
- For failure-path tests, use the existing `failNext("forceSync", BackendClientError.helperError(...))` plumbing the workflow tests already use.

## 6. Validation

Per `docs/orchestration-plan.md` §Validation Gates:

- `swift build` passes.
- `swift test --enable-code-coverage` passes; expect `AgendumMacWorkflowTests` count to grow by approximately +15 tests (#1-#15 in §5.2 plus the `testForceSyncBackendReportedErrorPostsFailureNotification` sibling under #3; #15's lighter form may fold into another test).
- `/opt/homebrew/bin/python3 -m unittest discover -s Tests` passes (Python helper unchanged).
- `/opt/homebrew/bin/python3 Scripts/python_coverage.py` passes (no helper changes; coverage stays at the post-PR-#19 baseline ≥ 91%).
- `git diff --check` passes.
- `swift run AgendumMac` smoke-launches without immediate crash, AND a manual click-through confirms:
  - Triggering a sync (toolbar Sync or `Cmd-Shift-S`) raises a notification banner when notifications are authorized; nothing visible when denied.
  - The dock tile shows a numeric badge after a sync that surfaces attention items, and the badge clears when a subsequent sync settles `hasAttentionItems == false`.
  - Settings → Notifications shows the right status string and the `Enable notifications` button transitions the user through the system permission dialog.

This change is not service-shaped (no new helper command, no new bridge surface, no IPC additions, no backend file changes). Per `~/.claude/crew/validation-principles.md` "When to skip" criteria, no change-specific integration-validation script is authored. The existing `swift test` gates plus the §6 manual notifications-and-badge smoke fully cover the surface.

## 7. Risks / out-of-scope

- **Dock-badge writes are independent of `UNUserNotificationCenter` authorization.** A user who denies notifications still sees the dock badge — `dockTile.badgeLabel` is not gated by notification authorization, so the two surfaces decouple cleanly. This is a feature: even users who silence banners still get the at-a-glance attention-item count on the dock.
- **Notification-spam risk under repeated `Cmd-Shift-S`.** The shared `agendum.sync.completed` identifier coalesces banners at the OS layer (later posts replace the prior one rather than stacking). In addition, the existing `isLoading` gating on `forceSync` (verify the menu/toolbar buttons gate on `!isLoading` per item 4 — `docs/design/04-shortcuts-menus.md`) bounds re-entrancy: while a sync is in flight, the user cannot fire another. Together these two controls bound the post rate without introducing a debounce. No additional debounce is added.
- **Notification grouping.** Out of scope. macOS's notification center already groups by app; we accept the system default rather than building per-workspace or per-source grouping.
- **Custom notification actions (Reply, Archive, Open Task).** Out of scope. `UNNotificationAction` + `UNNotificationCategory` plumbing is non-trivial (registration on app launch, action handler in `UNUserNotificationCenterDelegate`). The prototype's notifications are informational only.
- **Per-task notifications.** Out of scope. This item only fires on sync completion. A future checkpoint could fire per-task notifications when a new attention item arrives, but that requires diffing previous-vs-current task state and risks notification storms on first sync.
- **Notification sound customization.** Out of scope. `UNMutableNotificationContent.sound` defaults to `nil` (silent unless the user has set the system default sound). Custom sound bundles are deferred.
- **Critical Alerts.** Out of scope. `.criticalAlert` requires a special entitlement that Apple grants case-by-case; not appropriate for an agenda app.
- **Do Not Disturb / Focus modes.** Out of scope. The system handles DND filtering automatically; we don't need code changes.
- **Notification authorization revocation.** If the user grants then later revokes, the seam's `getNotificationSettings()` check returns `.denied` on the next post and silently no-ops. We don't need to listen for revocation events.
- **Sandbox / hardened-runtime / MAS interaction with notification entitlements.** Deferred per `docs/packaging.md` deferred decisions 1, 8, 9, 10. The runtime authorization request itself works in non-sandboxed and sandboxed apps without additional entitlements; the modern `UserNotifications` framework is sandbox-friendly. If item 5 lands and a future checkpoint flips the build to sandbox or MAS distribution, we may need to verify that `add(_:)` continues to deliver banners (sandboxed apps have stricter restrictions on background notifications). Documented as a §7 risk; not a blocker for the prototype.
- **Sandbox interaction with dock badge.** `NSApplication.shared.dockTile.badgeLabel` is sandbox-safe. No entitlement needed.
- **Dock-badge updates on a sandboxed app.** Mostly fine, but if the future MAS posture introduces a separate Application Service or LSUIElement mode (status-bar-only app), the dock tile concept changes and the badge becomes irrelevant. Deferred to packaging-decision routing.
- **Notification timing race.** If the user fires a sync, immediately switches workspaces, and the workspace switch's implicit reload settles before the sync completes, the `forceSync` post still fires with the original sync's outcome. The workspace switch does not cancel in-flight notifications. This is acceptable: the user sees a banner reflecting the action they took, even if the dashboard has moved on.
- **Testing notification posts under different authorization states.** We don't fake `UNUserNotificationCenter` authorization. The §5 tests exercise the seam's contract (suppressed vs not) rather than the system framework's behavior. A future hardening could introduce a `NotificationAuthorizing` seam to fake `getNotificationSettings()`; deferred because the current `RecordingNotifier(suppressed: true)` covers the same behavior with less surface area.
- **Stale dock badge after app quit.** macOS preserves `dockTile.badgeLabel` until the app is relaunched and explicitly clears it. The §4.1 `.task { backendStatus.setBadgeForAttentionCount() }` prime ensures the badge re-syncs to the live `hasAttentionItems` value on first appear, replacing whatever stale value the dock was showing.
- **Forward-compatibility of `state == "error"` classifier.** §3.5 treats any non-`"error"` value as a success outcome. If the helper protocol later adds a new failure-shaped state (e.g. `"degraded"`, `"partial"`), users will see a success banner for a partially-failed sync until both the classifier and a sibling test are updated. The fix is one line in `forceSync`; tracked in the orchestrator's External Deltas list when the helper protocol changes.
- **Synthesized `PresentedError` on branch (b) is notification-only.** §3.5 routes branch (b) through the shared `postSyncCompletedNotification(success:failure:)` helper by synthesizing `PresentedError(message: suffix)` with no `code` and no `recovery`. This synthesized error is intentionally never assigned to `self.error` — it exists only to feed the failure-body template. Item 3's structured-error surface remains the contract for thrown errors only; branch (b) deliberately diverges so the dashboard error caption is not painted by backend-reported sync states. Future hardening (e.g. per-state UX) is deferred to a later checkpoint.
- **Notification body on failure leaks structured-error message.** Acceptable. The structured `PresentedError.message` is already user-facing in the dashboard error caption; surfacing it in the notification body is consistent with that. Sensitive-information concerns (e.g. the body containing a token or a path) are not in scope because `PresentedError.message` is curated by the helper or by the `BackendClientError` mapping in `PresentedError.from(_:)`.

## 8. Open questions for orchestrator

Three crisp open questions remain after design self-review. Recommendations are stated; the orchestrator chooses.

1. **OQ1 — Integer count vs boolean for attention items.** Today the backend payload only exposes `hasAttentionItems: Bool` (per the `sync?.hasAttentionItems` accessor at `Sources/AgendumMacWorkflow/TaskWorkflowModel.swift:404`). The dock badge can therefore only show "1" when items are present — not the actual count. Should item 5 extend `SyncStatus` (and the helper) with an explicit integer `attentionItemsCount`, or ship the boolean-driven `0/1` badge first and revisit?
   - **Recommendation:** ship boolean-driven for item 5; defer the integer-count contract change to a separate follow-up. Reasoning: this item's stated scope (`docs/orchestration-plan.md` §Items, item 5) is "notifications + dock badge," not a backend protocol extension; bundling a contract change into the last live-slice item violates the per-item scope discipline (`docs/orchestration-plan.md` §Branch and PR Discipline). The `attentionItemCount` accessor is shaped to absorb the change without an App-layer diff, so the migration is one PR and zero churn. **Reviewer concurred.** Note: a future change to make `attentionItemCount` carry a real integer (vs the current 0/1) requires a Python helper-protocol change (`Backend/agendum_backend/helper.py`) and a sibling change to the bridge — track this in the orchestrator's External Deltas list rather than bundling into item 5.
2. **OQ2 — Routing: does `forceSync` directly invoke the badge seam, or only via `.onChange` on `hasAttentionItems`?** §3.6 routes badge updates through the App layer's `.onChange(of: backendStatus.hasAttentionItems)`. An alternative is to call `setBadgeForAttentionCount()` from the success/failure paths of `forceSync` (as a sibling of the notification post), which makes badge updates work even if the App layer forgets to wire `.onChange`.
   - **Recommendation:** keep the `.onChange`-only path (single writer). Reasoning: forcing the model to know about badge updates couples it to a presentation surface; the single-writer rule keeps the workflow target's contract clean. If a future window-less mode (e.g. menu-bar-only) loses the `.onChange`, the badge update can move into the model at that point — not preemptively. **Reviewer concurred.**
3. **OQ3 — Test for `defaultNotifier` / `defaultBadgeSetter` being wired by `convenience init()`.** §5.2 #15 considered two forms: the lighter form exercises the default `dockTile` seam in the test runner (a real but cheap side effect on the test process's dock tile), and the structural form just ensures the parameter list compiles. The lighter form is more meaningful but writes to a system surface during tests.
   - **Recommendation:** ship the structural form (no test that touches `dockTile`). Reasoning: `swift test` runs on CI macOS runners that may have unusual dock state; a write that mutates the runner's dock badge during test execution is a low-but-nonzero risk that's not worth the marginal coverage. The structural assertion (the convenience init compiles and `BackendStatusModel()` returns) plus the §5.2 tests #7-#9 covering the recording seam are sufficient. **Reviewer concurred.**

### Self-review (five-lens) pass-throughs

- **Correctness.** The `Notifying` and `BadgeSetting` seams mirror the existing `URLOpening` / `Pasteboarding` pattern exactly; defaults are isolated to a single static helper each. `forceSync` integration is a single `await notifier(...)` per terminal path. The `attentionItemCount` accessor is a one-liner over `hasAttentionItems`, and `setBadgeForAttentionCount()` is a one-liner over the seam. No new business logic enters the model.
- **Scope discipline.** Surface area is two source files plus one test file. No backend changes (OQ1 explicitly defers the integer-count contract change to a follow-up). No new SwiftPM products. No new entitlements. Matches `docs/orchestration-plan.md` §Branch and PR Discipline.
- **Missing risks.** §7 covers sandbox/MAS interactions, dock-badge persistence across launches, notification grouping/coalescing, authorization revocation, the workspace-switch-during-sync race, and the structured-error-in-notification-body posture. The five-lens pass added §7 entries for stale dock badge and notification timing race that the first draft omitted.
- **Test strength.** §5.2 covers success post, failure post, suppressed seam, identifier coalescing, badge transitions in both directions, the integer accessor's boolean-fallback, the count-zero contract, the "no implicit notifications on `refresh`/`selectWorkspace`" contract, and the "forceSync does not directly write the badge" contract. The convention of using lock-protected `@unchecked Sendable` recorders matches items 1 and 3.
- **Consistency with items 1-4.** Same eight-section layout. Same anchored-claim style (file paths + line numbers). Same SwiftUI-coverage-gap call-out. Same validation-gate enumeration delegated to `docs/orchestration-plan.md` §Validation Gates. Same `@unchecked Sendable` lock-protected test-seam pattern. Authorization-request UI is described but not unit-tested, matching the SwiftUI posture from items 1-4.
