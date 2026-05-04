# Research: Native Mac Data Store

> Stream B of the 2026-05-03 architecture-direction research. Captured verbatim from the `crew:researcher` run that produced it; cited claims should be re-verified before they harden into commitments. Companion docs: `docs/research/backend-engine.md`, `docs/research/architecture.md`, `docs/research/synthesis.md`.

## Decision context

`agendum-mac` will own its own data store. This stream evaluates the realistic options for a small, single-user, single-device macOS app and recommends one. The persistence layer interacts with both the backend-engine work (Stream A) and the architecture work (Stream C).

## Executive summary

- The decision under review is the 2026-04-28 "helper owns SQLite" rule. Once the Mac app owns its own data, the Python helper becomes a sync producer and the local store becomes the read source for the UI. This swaps the current bottleneck (every read/write crossing a stdio boundary) for a normal in-process query path.
- For a small (hundreds–few thousand records), single-user, single-device, read-heavy Mac app with an existing SQLite schema we want to keep on disk, the realistic shortlist is **GRDB.swift**, **SwiftData**, and **Core Data**. Realm is end-of-life on the Apple side; "plain SQLite via the C API" and bespoke file-based stores are not justified at this scale; SQLite.swift is viable but has weaker traction than GRDB; Fluent is a server ORM and not appropriate.
- Apple's current public guidance is "use SwiftData for new apps targeting macOS 14+, drop to Core Data when SwiftData lacks something you need." That guidance has not changed materially through WWDC 2025; the only headline SwiftData feature shipped that year was model inheritance. SwiftData remains the framework Apple is investing in, but well-known practitioners (Fatbobman, Wade Tregaskis, Peter Steinberger, Uhl Albert) continue to document concrete production pitfalls in iOS 17/18 and the macOS-archived-build CloudKit linkage bug. ([mjtsai.com](https://mjtsai.com/blog/2025/06/19/swiftdata-and-core-data-at-wwdc25/), [wadetregaskis.com](https://wadetregaskis.com/swiftdata-pitfalls/), [fatbobman.com](https://fatbobman.com/en/snippet/fix-synchronization-issues-for-macos-apps-using-core-dataswiftdata/))
- **Recommendation: GRDB.swift (v7+).** It maps onto the existing SQLite schema 1:1, has full Swift 6 / Sendable support, a mature `ValueObservation` story that feeds `@Observable` models cleanly, and is the wrapper Point-Free chose to build SQLiteData on. The migration story is "open the existing `~/.agendum/*.db` file", not "rewrite the schema." Fallback: SwiftData, only if we are willing to start from a clean store and accept iOS-17/18-era sharp edges in exchange for less code.
- First slice: stand up `AgendumMacStore` (a new SwiftPM target) backed by GRDB against a dedicated `agendum-mac.sqlite` in `Application Support`, port one query (`task.list` with current filters) and one mutation (mark seen), feed it into `BackendStatusModel` behind a new `TaskStoreProviding` protocol, and keep the Python helper running unchanged as a sync producer that writes through the same store via a narrow ingest API. No schema rewrite in slice 1.

---

## 1. Survey of options for a small Mac app in 2025–2026

### SwiftData
Apple's Swift-native framework, sitting on the Core Data engine. Minimum deployment is macOS 14 / iOS 17. WWDC 2025 added model inheritance, fixed the `@ModelActor` view-update bug, and let `Codable` properties appear in predicates — the bug fixes are back-deployed to iOS 17. ([mjtsai.com](https://mjtsai.com/blog/2025/06/19/swiftdata-and-core-data-at-wwdc25/))

Sharp edges that matter for a Mac app:
- macOS Release builds need explicit `CloudKit.framework` linkage even for non-CloudKit stores or initialization fails silently. ([fatbobman.com](https://fatbobman.com/en/snippet/fix-synchronization-issues-for-macos-apps-using-core-dataswiftdata/))
- Auto-save is unreliable; ordered relationships reorder; relationships set in `init` silently lose their parent FK; non-optional relationships are implicitly optional under the hood. ([wadetregaskis.com](https://wadetregaskis.com/swiftdata-pitfalls/))
- Migrations from a schema with non-optional transformable values can fail between `willMigrate` and `didMigrate` with "Can't find model for source store", which has burned multiple shipping apps. ([fatbobman.com](https://fatbobman.com/en/weekly/issue-116/))
- Performance and memory are noticeably worse than GRDB or Core Data; Uhl Albert filed test projects with Apple after his app's memory roughly doubled vs Core Data. ([mjtsai.com](https://mjtsai.com/blog/2024/10/16/returning-to-core-data/))

Migration story for an existing SQLite file: poor. SwiftData controls the schema, table names, and column shapes; you import data, you do not adopt a hand-written schema. The on-disk format would change.

Fit for agendum-mac: workable for a clean-slate store but actively hostile to "open the file the Python TUI already wrote."

### Core Data
Still the workhorse, still maintained, still what SwiftData runs on top of. Recommended by Apple itself in two cases: (a) you need to support macOS 13 or earlier, (b) you need a feature SwiftData hasn't reached (NSCompoundPredicate, advanced custom migrations, derived attributes, fetched properties, NSPersistentHistoryTracking with full filtering, Objective-C/extension sharing). ([fatbobman.com](https://fatbobman.com/en/posts/why-i-am-still-thinking-about-core-data-in-2026/))

For a fresh Mac app written in 2026, Core Data is the safe fallback to SwiftData but feels increasingly out of step with Swift 6 — its concurrency model, `NSManagedObjectContext` perform/performAndWait, and KVO underpinnings do not compose naturally with `@Observable` and structured concurrency. ([fatbobman.com](https://fatbobman.com/en/posts/why-i-am-still-thinking-about-core-data-in-2026/))

Migration story: you can attach an existing SQLite store as the persistent store, but the schema must be expressed as a `.xcdatamodeld`. Your existing tables (`tasks`, indexes) would have to be re-expressed as Core Data entities, which works but is friction.

### GRDB.swift
The mature, indie-favored Swift wrapper around SQLite. Latest is 7.10.0 (Feb 2026), Swift 6.1 / Xcode 16.3+, macOS 10.15+. Version 7 added the missing `Sendable` conformances and shipped a "Swift Concurrency and GRDB" guide; it is the most polished story among the SQLite-direct options for Swift 6 strict concurrency. ([github.com/groue/GRDB.swift](https://github.com/groue/GRDB.swift), [Swift Forums](https://forums.swift.org/t/grdb-7-beta/75018))

Strengths:
- You write the schema. The existing `SCHEMA` from `/Users/dseely/dev/agendum/src/agendum/db.py` (`tasks` table with `gh_url`, `gh_node_id`, `seen`, `last_changed_at`, etc., plus the `idx_tasks_*` indexes) can be adopted verbatim using `DatabaseMigrator`.
- `ValueObservation` gives Combine/AsyncSequence updates from arbitrary SQL queries; trivially feeds `@Observable` view models.
- `DatabaseQueue` (one writer, serialized) is exactly right for a single-user Mac app — `DatabasePool` (WAL + concurrent readers) is the upgrade path if reads ever get hot. The existing Python schema already runs in WAL.
- Type-safe records via `FetchableRecord` / `PersistableRecord` plus `Codable` integration.

Weaknesses:
- No CloudKit story out of the box (Point-Free's SQLiteData layers it on top if ever wanted).
- README does not name specific shipping apps; the "well-known indie apps use it" claim is widely repeated but I could not, in this run, verify a specific named consumer beyond Point-Free's own SQLiteData. Treat the "indie favorite" framing as community consensus, not citation-backed.

### SQLite.swift (stephencelis)
Lighter, more SQL-forward than GRDB, type-safe expression DSL, no observation primitives, no migration tool comparable to `DatabaseMigrator`, no first-class Combine/`@Observable` story. It works, but for a SwiftUI app in 2026 the GRDB ergonomics gap is large. Reasonable choice only if you specifically prefer the expression DSL.

### Plain SQLite via the C API
Justified only when you cannot take a dependency or want to bind into a non-Swift toolchain. For this app the cost (manual statement preparation, manual `sqlite3_*` lifetime management, manual concurrency, no observation) buys nothing GRDB doesn't already give us. NetNewsWire historically used FMDB (Objective-C wrapper) for this kind of low-level control, with the explicit rationale that "data is not objects" — that's the same philosophical lane GRDB sits in for Swift. ([talk.macpowerusers.com](https://talk.macpowerusers.com/t/i-was-desperately-searching-for-a-way-to-export-my-netnewswire-entries-and-i-accidentally-learned-that-its-all-stored-in-an-sqlite-database/27858), [inessential.com](https://inessential.com/2010/02/26/on_switching_away_from_core_data.html))

### Realm
End-of-life on the Apple side. MongoDB renamed Realm to Atlas Device SDKs in 2024 and announced deprecation; Atlas Device Sync shut down on 30 September 2025, with the SDKs themselves entering EoL the same day. Open-source code remains, but no further investment from MongoDB. **Do not adopt for new work.** ([MongoDB blog](https://www.mongodb.com/blog/post/realm-now-part-atlas-platform), [Couchbase blog](https://www.couchbase.com/blog/realm-mongodb-eol-day-2025/))

### File-based (JSON / plist / single Codable archive)
Right for prefs, draft state, "last selected workspace." Wrong for a few thousand records that need filtering by `(source, status, project, includeSeen)`, sorting, indexed lookups by `gh_url`/`gh_node_id`, and partial updates from a sync. Rewriting a 4k-row JSON blob on every sync tick is the wrong shape.

### Fluent / other server-side Swift ORMs
Vapor's Fluent is server ORM — it brings PostgreSQL/MySQL drivers, request-scoped contexts, and event-loop assumptions that do not belong in a SwiftUI app. Not credible on the Mac client side.

### SQLiteData (Point-Free)
A new option (1.6.1, March 2026) worth flagging even though it sits on top of GRDB. It gives you `@Table`/`@FetchAll`/`@FetchOne` macros that look like SwiftData's `@Model`/`@Query`, plus optional CloudKit sync and sharing, with full direct-SQL access underneath. ([github.com/pointfreeco/sqlite-data](https://github.com/pointfreeco/sqlite-data), [pointfree.co](https://www.pointfree.co/blog/posts/184-sqlitedata-1-0-an-alternative-to-swiftdata-with-cloudkit-sync-and-sharing)) For agendum-mac specifically: if you adopt GRDB now and later decide you want CloudKit, SQLiteData is a near-drop-in upgrade path. I would not pull it in on day one — the fewer macros in slice 1, the better — but it deserves to be on the radar.

---

## 2. Apple's current recommendation

Apple's framing across 2024–2026 has been consistent: SwiftData is the Swift-native, default persistence story for new apps that can deploy to macOS 14+/iOS 17+; Core Data remains supported and is the right answer when SwiftData lacks something. The 2024 "Adopting SwiftData" and "What's new in SwiftData" sessions positioned SwiftData as the path forward; WWDC 2025's session "SwiftData: Dive into inheritance and schema migration" continued that direction without retreating, and Apple back-deployed the WWDC 2025 bug fixes to iOS 17. ([Apple Developer](https://developer.apple.com/videos/play/wwdc2025/291/), [mjtsai.com](https://mjtsai.com/blog/2025/06/19/swiftdata-and-core-data-at-wwdc25/))

Where Apple itself still steers people elsewhere:
- Apps that need to deploy to macOS 13 / iOS 16.
- Apps that share a store with Objective-C extensions.
- Apps that need Core Data features SwiftData has not absorbed — advanced custom migrations, derived/transient attributes, NSCompoundPredicate complexity, full history-tracking filtering.

What Apple does not currently endorse: third-party persistence frameworks. It is a developer-community signal — not an Apple position — that GRDB is the de facto SQLite layer for serious indie/SwiftUI apps. That is worth being honest about in our decision log.

---

## 3. Concurrency & SwiftUI integration

Current architecture: `BackendClient` (actor, in `AgendumMacCore`) → `BackendStatusModel` (workflow `ObservableObject`/`@Observable`, in `AgendumMacWorkflow`) → SwiftUI views. The store layer plugs in below the workflow target. The constraints:

- Sync writes happen on a background path (whatever drives ingestion from the helper).
- UI reads from `BackendStatusModel` on the main actor.
- Swift 6 strict concurrency is in force in this repo's CI.

How each option lines up:

- **GRDB v7+**: writes go through a `DatabaseQueue` actor-like serial writer; reads are async via `db.read { ... }`. `ValueObservation.publisher(in:)` (Combine) and `.values(in:)` (`AsyncSequence`) both exist. `Sendable` conformances were added in v7. The natural shape is a `TaskStore` actor that owns a `DatabaseQueue` and exposes `func tasks(matching: Filters) async throws -> [TaskItem]` plus `func observe(matching:) -> AsyncStream<[TaskItem]>`; `BackendStatusModel` consumes the stream and republishes on the main actor. No `@MainActor` infection of the model layer.
- **SwiftData**: `@ModelActor` is the supported background-write pattern, but it has a documented gotcha — if the actor is initialized on the main thread, all calls are routed back to the main thread regardless of the `await` site. WWDC 2025 fixed the related "view-updates-don't-fire under @ModelActor" bug. `@Model` types are not `Sendable`; only `PersistentIdentifier` and `ModelContainer` are. Crossing actor boundaries means passing IDs and re-fetching, not passing model instances. Workable, but more rules to remember and the rules have shifted under us across releases. ([brightdigit.com](https://brightdigit.com/tutorials/swiftdata-modelactor/), [hackingwithswift.com](https://www.hackingwithswift.com/quick-start/swiftdata/how-swiftdata-works-with-swift-concurrency))
- **Core Data**: `NSManagedObjectContext` `perform { }` / `performAndWait { }` is the pattern; objects are not `Sendable`; you pass `NSManagedObjectID` between contexts. Mature and fine, but the verbosity stands out next to GRDB or SwiftData and requires more boilerplate to plug into `@Observable`.

For this codebase the GRDB shape composes most cleanly with the `actor` → `ObservableObject` → SwiftUI seam already in place.

---

## 4. Migration from existing SQLite

Today: `~/.agendum/<workspace>.db` is owned by the Python CLI/helper. The schema is in `/Users/dseely/dev/agendum/src/agendum/db.py` — a single `tasks` table, four indexes, WAL + busy_timeout 5s, 0700 dir / 0600 file. There are also concurrent CLI users.

Per option:

- **GRDB**: open the file directly. The existing schema is a perfectly normal SQLite schema; `DatabaseMigrator` can register version 1 as "schema already exists, no-op" and future versions can add columns/indexes. WAL is the default GRDB recommends. If we want the Mac app to own a different file (`Application Support/Agendum/agendum-mac.sqlite`) and treat the legacy `~/.agendum/*.db` as an import source, that's also a one-time copy.
- **SwiftData**: cannot adopt the existing schema verbatim. The path is "create a new SwiftData store, write a one-time importer that reads from the legacy SQLite and inserts via `ModelContext`." The on-disk format becomes Apple's, owned by the SwiftData store. Concurrent CLI access to the same file is no longer realistic.
- **Core Data**: similar to SwiftData — express the entity in `.xcdatamodeld`, optionally point the persistent store at the existing file, but you'll still want Core Data's metadata tables and entity layout, which means a controlled migration pass.

If the user wants the option to keep the Python TUI working against the same DB during transition, only **GRDB** preserves that without contortions.

---

## 5. Testing

- **GRDB**: trivial. `DatabaseQueue(path: ":memory:")` for in-memory, hand the writer to your store as a dependency, fixtures are `INSERT` statements (or record types) at test setup. The current architecture already has `AgendumBackendServicing` as a fakeable seam; adding `TaskStoreProviding` alongside it follows the same pattern.
- **SwiftData**: `ModelContainer(for: Schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))` works for unit tests, but Wade Tregaskis documents the SwiftUI-preview / test-fixture friction; some teams hit "Cannot preview in this file" with test model objects. Workable, more rough edges.
- **Core Data**: in-memory store via `NSPersistentStoreDescription(type: NSInMemoryStoreType)`. Solid, well-understood, but verbose.

For all three, the right shape here is the existing protocol seam: define `TaskStoreProviding`, give workflow tests a `FakeTaskStore`, and keep the GRDB-specific code in a thin adapter target.

---

## 6. Recommendation

**Pick: GRDB.swift (v7+).** Reasons, in priority order:

1. It is the only option that lets the Mac app open the existing `~/.agendum/*.db` schema without a rewrite. The current schema is small, hand-tuned, and already shipping; throwing it away to satisfy a framework's expectations would be a self-inflicted migration tax.
2. Swift 6 strict concurrency is settled (v7's added `Sendable` conformances), and `ValueObservation` is a clean fit for the existing `BackendStatusModel` observability pattern.
3. The current sharp edges around SwiftData on macOS — Release-build CloudKit linkage, migration failures, ordering bugs, memory regressions — are exactly the surface area we cannot afford to debug in a small prototype where the user expects "tasks load, sync runs, badge updates."
4. We are not asking for CloudKit, the App Store, or the things SwiftData is uniquely good at. We are asking for "a SQLite file with five queries and ten mutations, observable from SwiftUI." That is GRDB's lane.
5. The upgrade path is good. If we ever want SwiftData-ish ergonomics or CloudKit, Point-Free's SQLiteData sits on top of GRDB and is a believable migration target rather than a rewrite.

**Fallback: SwiftData.** Only if the user explicitly prefers Apple-only frameworks and is willing to (a) abandon the current SQLite file and migrate via a one-shot importer, (b) accept the documented pitfalls and the "macOS 14+ only" floor, (c) discover any new sharp edges as Apple iterates. Pick SwiftData only if you want fewer dependencies and are OK paying for it in debugging.

**Not recommended:** Core Data (functional but stylistically out of step with the rest of this codebase, and offers nothing GRDB doesn't here), Realm (EoL), SQLite.swift (weaker SwiftUI/observation story), plain C (no upside at this scale), file-based (wrong shape for the queries we need).

### Smallest first slice (concrete)

1. Add a SwiftPM target `AgendumMacStore` depending on GRDB 7.
2. Define a `TaskRecord` struct conforming to `FetchableRecord, PersistableRecord, Codable` mirroring the existing `tasks` table 1:1 (no shape change).
3. Add `TaskStore` actor: `init(path: URL)`, `func tasks(matching: TaskListFilters) async throws -> [TaskItem]`, `func observe(matching:) -> AsyncStream<[TaskItem]>`, `func markSeen(id:) async throws`. The mapping from `TaskRecord` to the existing `TaskItem` value type lives here.
4. Add `TaskStoreProviding` protocol in `AgendumMacWorkflow` and a `FakeTaskStore` for tests, mirroring the `AgendumBackendServicing` pattern recorded in the 2026-05-02 decision.
5. Wire `BackendStatusModel` to read tasks from `TaskStoreProviding` for the dashboard list view, leaving every other call (force-sync, manual-create, action mutations) on the Python helper untouched.
6. Keep the Python helper as the sync producer for now: it writes to its existing `~/.agendum/<workspace>.db`, and the Mac store opens the same file read-only or read/write under WAL. This validates the architectural change without committing to a new on-disk location.
7. New decision-log entry: "2026-05-03 — Mac app owns its read path via GRDB; helper retained as sync producer; on-disk schema unchanged for slice 1; Application Support relocation deferred."

That's enough to prove the choice on one screen, with a fakeable seam, no schema rewrite, no Python changes, and a clear rollback (delete the target, fall back to helper-RPC reads).

---

### Files referenced

- `/Users/dseely/dev/agendum/src/agendum/db.py` — current SQLite schema, indexes, WAL/busy_timeout settings.
- `/Users/dseely/dev/agendum-mac/Backend/agendum_backend/helper.py` — `_task_payload`, `task.list/get/createManual` shape.
- `/Users/dseely/dev/agendum-mac/Sources/AgendumMacWorkflow/TaskWorkflowModel.swift` — `TaskItem`, `TaskListFilters`, `BackendStatusModel`, `PresentedError`.
- `/Users/dseely/dev/agendum-mac/docs/decisions.md` — 2026-04-28 helper-owned-SQLite decision; 2026-05-02 protocol-seam pattern; 2026-05-02 packaging deferrals.
- `/Users/dseely/dev/agendum-mac/docs/plan.md` — milestone framing, "Whether Swift ever reads SQLite directly. Current bias: no" gate that this report is asking to flip.

### Sources

- [SwiftData and Core Data at WWDC25 — Michael Tsai](https://mjtsai.com/blog/2025/06/19/swiftdata-and-core-data-at-wwdc25/)
- [Returning to Core Data — Michael Tsai](https://mjtsai.com/blog/2024/10/16/returning-to-core-data/)
- [SwiftData pitfalls — Wade Tregaskis](https://wadetregaskis.com/swiftdata-pitfalls/)
- [Fixing macOS SwiftData/Core Data Sync: The CloudKit.framework Issue — Fatbobman](https://fatbobman.com/en/snippet/fix-synchronization-issues-for-macos-apps-using-core-dataswiftdata/)
- [Swift, SwiftUI & SwiftData: A Mature 2025 — Fatbobman Weekly #116](https://fatbobman.com/en/weekly/issue-116/)
- [Why I'm Still Thinking About Core Data in 2026 — Fatbobman](https://fatbobman.com/en/posts/why-i-am-still-thinking-about-core-data-in-2026/)
- [SwiftData: Dive into inheritance and schema migration — WWDC25](https://developer.apple.com/videos/play/wwdc2025/291/)
- [Key Considerations Before Using SwiftData — Fatbobman](https://fatbobman.com/en/posts/key-considerations-before-using-swiftdata/)
- [SQLiteData: A SwiftData Alternative — Point-Free](https://www.pointfree.co/blog/posts/168-sharinggrdb-a-swiftdata-alternative)
- [SQLiteData 1.0 — Point-Free](https://www.pointfree.co/blog/posts/184-sqlitedata-1-0-an-alternative-to-swiftdata-with-cloudkit-sync-and-sharing)
- [pointfreeco/sqlite-data on GitHub](https://github.com/pointfreeco/sqlite-data)
- [groue/GRDB.swift on GitHub](https://github.com/groue/GRDB.swift)
- [GRDB 7 beta — Swift Forums](https://forums.swift.org/t/grdb-7-beta/75018)
- [How SwiftData works with Swift concurrency — Hacking With Swift](https://www.hackingwithswift.com/quick-start/swiftdata/how-swiftdata-works-with-swift-concurrency)
- [Using ModelActor in SwiftData — BrightDigit](https://brightdigit.com/tutorials/swiftdata-modelactor/)
- [Realm is Now Atlas Device SDKs — MongoDB blog](https://www.mongodb.com/blog/post/realm-now-part-atlas-platform)
- [Realm/Atlas Device SDKs end-of-life — Couchbase blog](https://www.couchbase.com/blog/realm-mongodb-eol-day-2025/)
- [The Future: Realm is Deprecated/Dead — realm-swift discussion #8680](https://github.com/realm/realm-swift/discussions/8680)
- [NetNewsWire stores its database in SQLite — MPU forum thread](https://talk.macpowerusers.com/t/i-was-desperately-searching-for-a-way-to-export-my-netnewswire-entries-and-i-accidentally-learned-that-its-all-stored-in-an-sqlite-database/27858)
- [On switching away from Core Data — inessential.com (Brent Simmons)](https://inessential.com/2010/02/26/on_switching_away_from_core_data.html)
