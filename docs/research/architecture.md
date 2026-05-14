# Research: Architecture Patterns and Apple Alignment

> Stream C of the 2026-05-03 architecture-direction research. Captured verbatim from the `crew:researcher` run that produced it; cited claims should be re-verified before they harden into commitments. Companion docs: `docs/research/backend-engine.md`, `docs/research/data-store.md`, `docs/research/synthesis.md`.

## Decision context

The user wants the overall architecture to follow industry best practices and Apple Developer documentation recommendations as closely as possible. This stream evaluates the existing three-module shape (`AgendumMacCore` / `AgendumMacWorkflow` / `AgendumMac`) against Apple's current canonical app architecture and against industry SwiftUI patterns, then produces a punch list of deltas.

## Executive summary

- The current three-module split (`AgendumMacCore` / `AgendumMacWorkflow` / `AgendumMac`) is **already on the right shape**: it mirrors what Apple's Backyard Birds sample does (data target, UI target, app target). Don't dismantle it; rename and tighten it.
- The single most-aligned change you can make is **migrating `BackendStatusModel` from `ObservableObject` + 11 `@Published` fields to `@Observable`** — this is what Apple has been actively recommending since WWDC23 ("Discover Observation in SwiftUI") and what every 2024–2026 sample app uses. The migration itself is mechanical (delete `ObservableObject`, delete `@Published`, add `@Observable`); the gotchas are around `@MainActor` interaction.
- Apple's canonical small-app shape per Apple docs and WWDC23 is: `App` + `Scene` + `@Observable` model objects placed in `@State` at the root, propagated via `@Environment`, edited via `@Bindable` — **not** MVVM-with-Combine and **not** TCA.
- TCA is a defensible choice — Lickability defaults to it for new apps — but it's over-spec for a single-window dashboard with one model object and one I/O actor. Adopt the TCA *idea* (one `@Dependency`-style seam for your services) without adopting the framework.
- The current `actor AgendumBackendClient` + `@MainActor` view-model split is the Swift-6-correct shape. Swift 6.2's "Approachable Concurrency" makes this even easier (main-actor-by-default), but you don't need to chase 6.2 today.
- Navigation: `NavigationSplitView` is the Apple-recommended Mac shape. The missing pieces are typed `@SceneStorage`-backed selection state for state restoration and a typed deep-link entry point.
- Testing seam (`AgendumBackendServicing` protocol + `FakeBackend`) is idiomatic and matches what Sundell, swift-dependencies, and TCA all converge on. Keep it. Optional upgrade: switch from XCTest to `swift-testing` once the suite stabilizes.
- Table-stakes Mac polish gaps: structured `os.Logger` subsystems, `@SceneStorage` for window/sidebar/selection, deep-link `onOpenURL`, accessibility audit, localization scaffold, no crash reporter wired.
- Recommendation: do a small "modernization" PR (Observable migration + Logger + SceneStorage + module rename) **before** the standalone-backend and data-store changes land, so those changes are easier to review.

## 1. What Apple actually recommends in 2025–2026

Apple's official guidance, as captured in WWDC23 session 10149 *Discover Observation in SwiftUI* and the *Migrating from the Observable Object protocol to the Observable macro* doc, is a **three-question decision tree** for any model object in a SwiftUI app:

> "Does this model need to be state of the view itself? If so, use `@State`.
> Does this model need to be part of the global environment of the application? If so, use `@Environment`.
> Does this model just need bindings? If so, use the new `@Bindable`.
> And if none of these questions have the answer as yes, just use the model as a property of your view."
> — WWDC23 *Discover Observation in SwiftUI*

For new code Apple says explicitly: *"For new development, using Observable is the easiest way to get started. And for existing applications, using Observable can simplify your models and improve performance when adding new features."* `ObservableObject` is now a legacy path; Apple has not retired it, but every 2024–2025 sample (Backyard Birds, Destination Video, Landmarks-as-modules) uses `@Observable`.

The canonical small-app skeleton Apple presents is:

```swift
@main struct App: SwiftUI.App {
    @State private var model = AppModel()      // one root @Observable
    var body: some Scene {
        WindowGroup { RootView().environment(model) }
        Settings { SettingsView() }
    }
}
```

Async I/O is recommended to live behind `actor`s and `async`/`await` calls; `@Published` + Combine pipelines are no longer the recommended primitive for new code. Combine is still supported but absent from new sample apps.

Sources: [Discover Observation in SwiftUI (WWDC23 10149)](https://developer.apple.com/videos/play/wwdc2023/10149/), [Migrating from the Observable Object protocol to the Observable macro](https://developer.apple.com/documentation/SwiftUI/Migrating-from-the-observable-object-protocol-to-the-observable-macro), [Backyard Birds sample](https://developer.apple.com/documentation/swiftui/backyard-birds-sample), [What's new in SwiftUI WWDC24](https://developer.apple.com/videos/play/wwdc2024/10144/), [What's new in SwiftUI WWDC25](https://developer.apple.com/videos/play/wwdc2025/256/).

## 2. Industry SwiftUI architecture patterns and fit for agendum-mac

**MV / "model-view" with `@Observable` (the Apple-aligned default).** Mohammad Azam's MV-pattern argument is that SwiftUI is *already* an MV framework — `View` is the V, `@Observable` types are the M, and the "VM" layer of MVVM tends to duplicate what SwiftUI's body re-evaluation already does. *Fit for agendum-mac:* very high. The current `BackendStatusModel` is already effectively the M; switching to `@Observable` gets you to the canonical shape with no architectural reshuffle. Source: [SwiftUI Architecture — A Complete Guide to the MV Pattern Approach](https://betterprogramming.pub/swiftui-architecture-a-complete-guide-to-mv-pattern-approach-5f411eaaaf9e).

**MVVM (still common, but contested in SwiftUI).** Apple Developer Forums consensus on "Which architecture is best for SwiftUI" is that MVVM/MVC are not what SwiftUI was built for: `@State`/`@Observable` essentially are the binding mechanism MVVM provides on UIKit. Source: [Apple Developer Forums thread 735760](https://developer.apple.com/forums/thread/735760). *Fit:* the current code is MV in spirit (one observable model, no separate VMs); leave it that way.

**TCA (The Composable Architecture) by Point-Free.** TCA gives you: one `State` value, explicit `Action`s, a `Reducer` for transitions, `Effect`s for I/O, `@Dependency` for testable seams, `@ObservableState` to integrate with `@Observable`. Lickability *defaults* to TCA for new apps. Strengths: every state transition is traceable; testing is exhaustive; complex flows (auth, multi-step sync, undo) become tractable. Costs: meaningful learning curve, large dependency footprint, a lot of ceremony for a one-screen app. *Fit for agendum-mac:* over-spec. The current model has 11 published fields and ~20 methods, fits in one file, and has a single I/O dependency already mocked behind a protocol. The TCA *patterns worth stealing* are (a) the `@Dependency` injection style — your `AgendumBackendServicing` already does this — and (b) the discipline of letting all state transitions go through one entry point, which `BackendStatusModel` already enforces by being an actor-isolated class. Sources: [swift-composable-architecture README](https://github.com/pointfreeco/swift-composable-architecture), [Lickability swift-best-practices](https://github.com/Lickability/swift-best-practices), [Lickability: How to learn TCA](https://lickability.com/blog/how-to-learn-tca/).

**Clean architecture / VIPER.** Naumov's *Clean Architecture for SwiftUI* (Presentation → Interactors+AppState → Repositories) is well-articulated but explicitly aimed at *complex* apps that need multiple data sources, deep linking, and 90%+ test coverage; he himself notes SwiftUI's declarative nature reduces the need for VIPER's ceremony. *Fit:* no — three layers around one Python helper is over-abstraction. Source: [Clean Architecture for SwiftUI](https://nalexn.github.io/clean-architecture-swiftui/).

**"Just SwiftUI" with services (Sundell school).** Initializer- or environment-injected services (functions or protocols) consumed by `@Observable` models. Sundell's "different flavors of dependency injection" essay and his "simple Swift dependency injection with functions" post are the canonical references — and **this is what agendum-mac already does** with `AgendumBackendServicing`. Sources: [Sundell — Different flavors of DI](https://www.swiftbysundell.com/articles/different-flavors-of-dependency-injection-in-swift/), [Sundell — DI with functions](https://www.swiftbysundell.com/articles/simple-swift-dependency-injection-with-functions/).

**Coordinators.** Coordinators in their UIKit form aren't idiomatic in SwiftUI. The 2024–2025 SwiftUI equivalent is `NavigationStack(path: $path)` with a `NavigationPath` (or typed `[Route]`) on a navigation model. Source: [Modern SwiftUI Navigation](https://fatbobman.com/en/posts/new_navigator_of_swiftui_4/), [The SwiftUI cookbook for navigation (WWDC22)](https://developer.apple.com/videos/play/wwdc2022/10054/).

**Verdict:** stay on the MV-with-`@Observable` track Apple recommends; steal the *seam* discipline from TCA without adopting the framework.

## 3. Module / package layering vs. Apple's own samples

Apple's Backyard Birds project uses Xcode-project targets but the layering is exactly what you have:

| Backyard Birds | agendum-mac (today) | Notes |
|---|---|---|
| `BackyardBirdsData` | `AgendumMacCore` | Models + persistence/transport. |
| `BackyardBirdsUI` | `AgendumMacWorkflow` (mostly) | Reusable view-state types. |
| `Multiplatform` (app) | `AgendumMac` | Scene + views + commands. |
| `LayeredArtworkLibrary` | — | N/A for agendum. |

So the three-target SwiftPM split is *idiomatic* for an app of this size. The friction points specific to agendum-mac:

- `AgendumMacWorkflow` mixes **view-model state** (`BackendStatusModel`), **value types views consume** (`TaskItem`, `TaskSource`), **command descriptors** (`TaskDashboardCommand`), and **AppKit-flavored seams** (`URLOpening`, `Pasteboarding`, `Notifying`, `BadgeSetting`). Backyard Birds keeps cross-platform UI types in `BackyardBirdsUI` and keeps platform-specific glue in the app target. Consider moving the `Notifying` / `BadgeSetting` *default implementations* (which import AppKit and UserNotifications) into the executable target, leaving `AgendumMacWorkflow` AppKit-free except for the `@Sendable` typealiases.
- `AgendumMacCore` is a clean process-boundary client — keep it. The 605-LOC file holds 14 envelope types plus the actor; that's fine and matches what Apple sample apps do for Codable wire types.
- *Renaming to consider:* `AgendumMacCore` → `AgendumBackend` (drops the redundant "Mac"), `AgendumMacWorkflow` → `AgendumApp` or `AgendumFeature` (Backyard Birds and TCA both use `Feature`). Cosmetic, but it improves grep-ability when the backend-engine and data-store work lands.

The layering shouldn't get *deeper* (no Repository/Interactor/Presenter layer for one screen). It can get *wider* later if you split features (e.g. `AgendumWorkspaces`, `AgendumSync`) — defer until there's a second screen.

Source: [apple/sample-backyard-birds](https://github.com/apple/sample-backyard-birds).

## 4. Concurrency and isolation

The current shape (`public actor AgendumBackendClient` + `@MainActor public final class BackendStatusModel: ObservableObject`) is the **textbook Swift 6 SwiftUI shape**: I/O on a non-Main actor, view state on the Main actor, sendable value types crossing the boundary. This is exactly what every 2024–2025 concurrency guide recommends. Sources: [Approachable Concurrency in Swift 6.2 — SwiftLee](https://www.avanderlee.com/concurrency/approachable-concurrency-in-swift-6-2-a-clear-guide/), [Hacking with Swift — Swift 6 complete concurrency](https://www.hackingwithswift.com/swift/6.0/concurrency).

Things to be aware of:

1. **`@Observable` + `@MainActor` interaction.** Per Philippe Hausler on Swift Forums: *"@Observable is a bring-your-own-synchronization-type however. So if you need thread safety you should provide it."* The standard pattern when the model is also the SwiftUI source of truth is `@Observable @MainActor final class Model { ... }`. Don't be tempted to drop `@MainActor` just because `@Observable` works without it. Source: [Swift Forums — @Observable conflicting with @MainActor](https://forums.swift.org/t/observable-macro-conflicting-with-mainactor/67309).

2. **Avoid manual `MainActor.run` from `@MainActor` contexts.** Your `defaultBadgeSetter` uses `MainActor.assumeIsolated` — that's the right primitive when called from a `@Sendable` closure that you *know* is invoked on Main. Just leave a comment explaining the invariant.

3. **`ObservationRegistrar` outside SwiftUI.** If you ever need to observe `BackendStatusModel` from non-view code, prefer the `withObservationTracking` API rather than re-introducing Combine. Source: [Donny Wals — Observing properties on an @Observable class outside of SwiftUI views](https://www.donnywals.com/observing-properties-on-an-observable-class-outside-of-swiftui-views/).

4. **Anti-patterns to keep avoiding:** `await MainActor.run` from already-Main-isolated code, blocking heavy work on Main inside `Task { }` from a view (Use Your Loaf has a writeup on this), and `@unchecked Sendable` shortcuts to silence the compiler. Source: [SwiftUI Tasks Blocking the MainActor — Use Your Loaf](https://useyourloaf.com/blog/swiftui-tasks-blocking-the-mainactor/).

5. **SwiftData interaction (forward-looking).** WWDC24 *Track model changes in your SwiftUI app* demonstrates SwiftData working with `@Observable` directly via the `@Model` macro; the recommended pattern is to keep the `ModelContainer`/`ModelContext` on Main and do bulk imports from a `ModelActor`. If the data-store research stream lands SwiftData, this is the shape to plan for; if it lands GRDB or raw SQLite, keep DB access behind your existing `actor`.

## 5. Observation framework migration (BackendStatusModel)

**Effort: small. Risk: low. Win: meaningful.**

Mechanical changes:
- Delete `: ObservableObject` conformance.
- Delete every `@Published`.
- Add `@Observable` above `@MainActor public final class BackendStatusModel`.
- In `AgendumMacApp.swift`, replace `@StateObject private var model` with `@State private var model = BackendStatusModel()` (note: `@StateObject` is for reference types under the old protocol; `@State` works for `@Observable` reference types because the property wrapper is now agnostic to ref/value).
- Replace `@ObservedObject` with plain property declarations; replace `@EnvironmentObject` with `@Environment(BackendStatusModel.self)`; views that need bindings against fields use `@Bindable var model`.

Gotchas:
- `Combine` import in `TaskWorkflowModel.swift` becomes unnecessary — drop it.
- Anything currently observing `model.objectWillChange` (rare in this code) needs to be moved to `withObservationTracking`.
- `@Observable` does NOT auto-isolate to Main — keep the explicit `@MainActor`.
- `import Combine` may be needed to stay if you publish through `AsyncStream`s elsewhere — confirm at migration time.
- Some `@Published private(set) var` fields will need `private(set) var` only — `@Observable` macro respects access modifiers fine.
- One subtle case: `@Published public internal(set) var selectedTaskID` — `@Observable` does not change the externally writable contract; the field becomes a normal `var` with the same access level.

Reasons to *stay* on `ObservableObject`: only if you must support macOS 13 or earlier, or if you have heavy Combine pipelines. Neither applies — `Package.swift` already targets `.macOS(.v14)`.

Per WWDC23: *"Changing from ObservableObject to the new '@Observable' macro was mostly just deleting annotations."* Plan ~30 minutes of code change + test run.

## 6. Navigation, Settings, deep-linking, state restoration

Apple's recommended Mac shell as of WWDC22's *SwiftUI cookbook for navigation* and reinforced through WWDC24:

- `NavigationSplitView` for sidebar + content (+ optional detail). The current dashboard already uses this.
- For programmatic and deep-link-ready navigation, store selection state on the model: `@State var selectedTaskID: TaskItem.ID?` and `@State var detailRoute: DetailRoute = .none`. (You already have `selectedTaskID`.)
- For state restoration: wrap that selection state in `@SceneStorage("selectedTaskID")` (Codable-friendly types only — `Int` is fine). On Mac with multiple windows, `@SceneStorage` scopes per-scene, which is what you want.
- For deep linking: handle `.onOpenURL { url in route(url) }` on the root scene's content view.
- Settings: a dedicated `Settings { SettingsView() }` scene gets you Cmd-, automatically. Source: [Sarunw — Keyboard shortcuts in SwiftUI](https://sarunw.com/posts/swiftui-keyboard-shortcuts/), [Daniel Saidi — Customizing the macOS menu bar in SwiftUI](https://danielsaidi.com/blog/2023/11/22/customizing-the-macos-menu-bar-in-swiftui), [Nil Coalescing — State restoration with SceneStorage](https://nilcoalescing.com/blog/UsingSceneStorageForStateRestorationInSwiftUIApps/).

Current code: AgendumMacApp.swift has `Settings`, `WindowGroup`, sidebar, detail. *Missing:* `@SceneStorage` for selected task / sidebar visibility / window position; no `.onOpenURL`; no typed deep-link route. These are pure additions, not refactors.

## 7. Testing seams

Your `AgendumBackendServicing` + `FakeBackend` pattern is idiomatic for 2025–2026. It maps cleanly onto Sundell's "protocols-as-seams" approach and onto what swift-dependencies wraps — the latter is *exactly* "an API inspired by SwiftUI's environment, powered by Swift's task local machinery" (Stephen Celis on Swift Forums). You don't need swift-dependencies until you have several services injected at multiple levels; one protocol seam beats one library dependency.

Layered testing recommendation:
- **Pure value-type tests** (TaskItem, TaskSource, PresentedError factories): swift-testing or XCTest, no fakes needed.
- **Workflow tests** (BackendStatusModel against `FakeBackend`): the current setup. Add tests for the new `@Observable` change-tracking path if you switch.
- **UI tests**: you don't have these and don't need them yet; the manual smoke list in `docs/testing.md` is fine until the live slice stabilizes.
- **Integration tests** through the JSONL helper: keep what you have.

`swift-testing` (WWDC24) is worth adopting *for new tests* once your XCTest suite is otherwise stable: parallelism by default, `#expect` macros, parameterized tests via `@Test(arguments:)`. It does not yet cover performance/UI testing, so XCTest stays for those. Don't migrate the existing suite as part of this architecture work; let it accrete. Source: [Hello Swift Testing, Goodbye XCTest — Leo](https://leocoout.medium.com/welcome-swift-testing-goodbye-xctest-7501b7a5b304), [Swift-dependencies Forums announcement](https://forums.swift.org/t/introducing-swift-dependencies-a-dependency-injection-library-inspired-by-swiftuis-environment/62476).

`@TaskLocal` is worth knowing about for the *one* legitimate niche where you want a value (e.g. a fake clock) propagated through async code without threading it through every signature. It's a more advanced tool than you need today.

## 8. Table-stakes Mac polish

| Area | Apple-recommended hook | Currently present? |
|---|---|---|
| Settings scene | `Settings { … }` + `.keyboardShortcut(",")` is automatic | Yes |
| App menu commands | `.commands { CommandGroup(...) }` | Yes (good) |
| Keyboard shortcuts | `.keyboardShortcut(_:modifiers:)` on commands; avoid stealing system shortcuts | Yes |
| Notifications | `UNUserNotificationCenter` (you've got it) | Yes |
| Dock badge | `NSApplication.shared.dockTile.badgeLabel` | Yes |
| Deep links | `.onOpenURL { … }` on root content | **No** |
| State restoration | `@SceneStorage` (per-scene), `@AppStorage` (app-wide prefs) | **Partial — none seen for selection/sidebar** |
| Logging | `os.Logger` with subsystem `com.danseely.agendum-mac` and per-area categories (`backend.client`, `workflow.sync`, `ui.dashboard`) | **No** — no `os.Logger` references; using `print` or nothing |
| Crash reporting | `MetricKit` for system metrics; third-party (Sentry/Crashlytics) optional | **No** |
| Accessibility | `.accessibilityLabel` / `.accessibilityValue` on toolbar/list rows; respect Dynamic Type with `.dynamicTypeSize`; VoiceOver smoke test | Likely thin — audit |
| Localization | `String(localized:)` instead of literals, `Localizable.xcstrings` | **No** — strings are inline literals |
| Error presentation | `.alert(item: $error)` or sheet; `LocalizedError` for system surfaces | Inline captions; `PresentedError` is a custom struct (good shape) — consider conforming to `LocalizedError` for AppKit/Foundation interop |

Priority order for a small follow-up PR: `os.Logger` (largest debuggability win), `@SceneStorage` for selection/sidebar, `.onOpenURL` stub. Localization and accessibility audit can be a separate "polish" milestone.

Sources: [SwiftLee — OSLog and Unified Logging](https://www.avanderlee.com/debugging/oslog-unified-logging/), [Donny Wals — Modern logging with the OSLog framework](https://www.donnywals.com/modern-logging-with-the-oslog-framework-in-swift/), [SwiftUI for Mac 2024 — TrozWare](https://troz.net/post/2024/swiftui-mac-2024/).

## 9. Concrete deltas vs. the current code

**Land before standalone-backend / data-store work** (small, scoped, makes those PRs easier to review):
1. Migrate `BackendStatusModel` to `@Observable`; drop `ObservableObject`/`@Published`/`Combine`. (~30 min change, mostly mechanical.) Update `@StateObject`/`@EnvironmentObject` call sites in `AgendumMacApp.swift` to `@State`/`@Environment`/`@Bindable`.
2. Introduce `os.Logger` with subsystem `com.danseely.agendum-mac` and categories `backend`, `workflow`, `ui`. Replace any `print` / silent error swallowing with `logger.error`, `logger.notice`, `logger.debug`.
3. Add `@SceneStorage` for `selectedTaskID`, sidebar `NavigationSplitViewVisibility`, and active filter source. (Pure addition.)
4. Move AppKit/UNUserNotificationCenter *default implementations* (`defaultURLOpener`, `defaultPasteboard`, `defaultNotifier`, `defaultBadgeSetter`) out of `AgendumMacWorkflow` into the executable target. The protocol typealiases stay in workflow. This makes the workflow target AppKit-free and faster to test.
5. Optional: rename `AgendumMacCore` → `AgendumBackend` and `AgendumMacWorkflow` → `AgendumFeature` (or `AgendumApp`).

**Land alongside the standalone-backend work** (these decisions interact with backend ownership):
6. If the backend research stream picks "Swift owns the engine," collapse the JSONL `BackendClient` into typed actor methods over an in-process service. Either way, keep the `AgendumBackendServicing` protocol — it's the test seam.
7. Add a `@Dependency`-style services struct (clock, notifier, opener) injected on the model. Hand-rolled struct is fine; only adopt swift-dependencies if it grows past 3–4 services.

**Land alongside the data-store work:**
8. If SwiftData lands, push `BackendStatusModel.tasks: [TaskItem]` toward a `@Query`-driven view (or keep a curated cache if filtering needs are richer than `@Query` predicates).
9. Settle whether the model owns the `ModelContainer` (Apple's pattern) or the actor does.

**Deferred polish (own milestone):**
10. Localization scaffold (`Localizable.xcstrings`, `String(localized:)` everywhere).
11. Accessibility audit + Dynamic Type honoring.
12. `MetricKit` crash/hang reporting hookup.
13. `.onOpenURL` deep-link surface (when there's a real URL scheme).
14. Migrate tests to `swift-testing` opportunistically.

## 10. Recommendation and target architecture

**Target architecture (text diagram).**

```
┌─────────────────────────────────────────────────────────────┐
│ AgendumMac (executable)                                     │
│   AgendumMacApp: App                                        │
│     WindowGroup { DashboardView }                           │
│     Settings { SettingsView }                               │
│     .commands { ... }                                       │
│   Default seams (AppKit/UN): URLOpener, Pasteboard,         │
│     Notifier, BadgeSetter                                   │
└────────────┬────────────────────────────────────────────────┘
             │ imports
┌────────────▼────────────────────────────────────────────────┐
│ AgendumFeature (was AgendumMacWorkflow)                     │
│   @Observable @MainActor BackendStatusModel                 │
│   Value types: TaskItem, TaskSource, PresentedError,        │
│                TaskListFilters, TaskDashboardCommand        │
│   Protocol seam: AgendumBackendServicing                    │
│   Sendable typealiases: URLOpening, Pasteboarding, ...      │
│   os.Logger("com.danseely.agendum-mac", category: ...)      │
└────────────┬────────────────────────────────────────────────┘
             │ imports
┌────────────▼────────────────────────────────────────────────┐
│ AgendumBackend (was AgendumMacCore)                         │
│   public actor AgendumBackendClient                         │
│   Codable wire types: Workspace, AuthStatus, SyncStatus,    │
│                       AgendumTask, BackendErrorPayload, ... │
│   BackendClientError                                        │
└─────────────────────────────────────────────────────────────┘
```

**Migration order.**
1. *PR 1 (architecture-modernization):* `@Observable` migration + `os.Logger` + `@SceneStorage` + AppKit-defaults moved out of workflow target. Optional rename. **Do this first** — small, mechanical, reviewable, makes everything else easier.
2. *PR sequence (standalone backend):* whatever the backend research stream proposes; the seam survives any of those choices.
3. *PR sequence (data store):* whatever the data-store stream proposes; if it's SwiftData, plan `@Model` types in `AgendumBackend` (or a sibling target) and a `ModelActor` for bulk writes.
4. *PR (polish milestone):* Localization, accessibility, `.onOpenURL`, MetricKit.

**Standing architectural decisions to add to `docs/decisions.md`.**
- Use `@Observable` for all new model objects; `ObservableObject` is reserved for code that must support pre-macOS-14 hosts.
- Apple's three-question model decides property-wrapper choice (`@State` / `@Environment` / `@Bindable`); avoid `@StateObject` / `@ObservedObject` / `@EnvironmentObject` in new code.
- All cross-actor boundaries use `Sendable` value types; `@MainActor` on view-state classes is explicit; I/O lives on `actor`s.
- Each module gets its own `os.Logger` category under subsystem `com.danseely.agendum-mac`.
- Test seams are protocol-typed and live in the workflow target; AppKit/UN/Combine imports stay out of the workflow target.
- Navigation state for state restoration uses `@SceneStorage`; deep links arrive through `.onOpenURL`.
- Adopt `swift-testing` for *new* test files; do not migrate existing XCTest suites until they need rework.
- Do not adopt TCA, Clean Architecture, VIPER, or a generic DI container at current scope; revisit if the app grows past three feature surfaces.

---

**Files inspected:**
- /Users/dseely/dev/agendum-mac/Package.swift
- /Users/dseely/dev/agendum-mac/Sources/AgendumMacCore/BackendClient.swift
- /Users/dseely/dev/agendum-mac/Sources/AgendumMacWorkflow/TaskWorkflowModel.swift
- /Users/dseely/dev/agendum-mac/Sources/AgendumMac/AgendumMacApp.swift (structural outline only)
- /Users/dseely/dev/agendum-mac/docs/{plan,decisions,testing}.md

**Sources:**
- [WWDC23 — Discover Observation in SwiftUI](https://developer.apple.com/videos/play/wwdc2023/10149/)
- [Apple — Migrating from the Observable Object protocol to the Observable macro](https://developer.apple.com/documentation/SwiftUI/Migrating-from-the-observable-object-protocol-to-the-observable-macro)
- [Apple — Backyard Birds sample](https://developer.apple.com/documentation/swiftui/backyard-birds-sample) and [GitHub apple/sample-backyard-birds](https://github.com/apple/sample-backyard-birds)
- [WWDC24 — What's new in SwiftUI](https://developer.apple.com/videos/play/wwdc2024/10144/)
- [WWDC25 — What's new in SwiftUI](https://developer.apple.com/videos/play/wwdc2025/256/)
- [WWDC22 — The SwiftUI cookbook for navigation](https://developer.apple.com/videos/play/wwdc2022/10054/)
- [Apple Developer Forums — Which architecture is best for SwiftUI](https://developer.apple.com/forums/thread/735760)
- [Swift Forums — @Observable conflicting with @MainActor](https://forums.swift.org/t/observable-macro-conflicting-with-mainactor/67309)
- [Swift Forums — Introducing swift-dependencies](https://forums.swift.org/t/introducing-swift-dependencies-a-dependency-injection-library-inspired-by-swiftuis-environment/62476)
- [Point-Free — swift-composable-architecture](https://github.com/pointfreeco/swift-composable-architecture)
- [Lickability — swift-best-practices](https://github.com/Lickability/swift-best-practices) and [How to learn TCA](https://lickability.com/blog/how-to-learn-tca/)
- [Naumov — Clean Architecture for SwiftUI](https://nalexn.github.io/clean-architecture-swiftui/)
- [Azam — SwiftUI Architecture: A Complete Guide to MV Pattern](https://betterprogramming.pub/swiftui-architecture-a-complete-guide-to-mv-pattern-approach-5f411eaaaf9e)
- [Sundell — Different flavors of dependency injection in Swift](https://www.swiftbysundell.com/articles/different-flavors-of-dependency-injection-in-swift/)
- [Sundell — Simple Swift dependency injection with functions](https://www.swiftbysundell.com/articles/simple-swift-dependency-injection-with-functions/)
- [SwiftLee — Approachable Concurrency in Swift 6.2](https://www.avanderlee.com/concurrency/approachable-concurrency-in-swift-6-2-a-clear-guide/)
- [SwiftLee — OSLog and Unified Logging](https://www.avanderlee.com/debugging/oslog-unified-logging/)
- [Donny Wals — Observing properties on @Observable outside SwiftUI views](https://www.donnywals.com/observing-properties-on-an-observable-class-outside-of-swiftui-views/)
- [Use Your Loaf — SwiftUI Tasks Blocking the MainActor](https://useyourloaf.com/blog/swiftui-tasks-blocking-the-mainactor/)
- [Fatbobman — Modern SwiftUI Navigation deep dive](https://fatbobman.com/en/posts/new_navigator_of_swiftui_4/)
- [Nil Coalescing — State restoration with SceneStorage](https://nilcoalescing.com/blog/UsingSceneStorageForStateRestorationInSwiftUIApps/)
- [Sarunw — Keyboard shortcuts in SwiftUI](https://sarunw.com/posts/swiftui-keyboard-shortcuts/)
- [Saidi — Customizing the macOS menu bar in SwiftUI](https://danielsaidi.com/blog/2023/11/22/customizing-the-macos-menu-bar-in-swiftui)
- [Hacking with Swift — Swift 6 complete concurrency](https://www.hackingwithswift.com/swift/6.0/concurrency)
- [Leo — Hello Swift Testing, Goodbye XCTest](https://leocoout.medium.com/welcome-swift-testing-goodbye-xctest-7501b7a5b304)
