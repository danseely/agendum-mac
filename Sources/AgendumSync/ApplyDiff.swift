import Foundation
import AgendumMacStore

// MARK: - Writer seam

/// Narrow seam over `TaskStore` covering exactly the writes the syncer needs.
/// Owned by `AgendumSync` (the consumer). `TaskStore` conforms via the
/// extension below so production wiring is one type. Tests substitute a fake.
public protocol SyncTaskWriter: Sendable {
    func findTaskID(forGHURL ghURL: String) async throws -> Int?

    @discardableResult
    func insertSyncedTask(
        title: String,
        source: String,
        status: String,
        ghURL: String?,
        ghRepo: String?,
        ghNumber: Int?,
        ghAuthor: String?,
        ghAuthorName: String?,
        project: String?,
        tags: String?,
        now: String
    ) async throws -> Int

    func applySyncUpdate(
        id: Int,
        title: String?,
        source: String?,
        status: String?,
        project: String?,
        ghRepo: String?,
        ghNumber: Int?,
        ghAuthor: String?,
        ghAuthorName: String?,
        tags: String?,
        resetSeen: Bool,
        now: String
    ) async throws
}

extension TaskStore: SyncTaskWriter {}

// MARK: - Result

/// Tally returned by `applyDiff`. `changes` counts every row touched (created,
/// updated-with-fields, race-merged, or closed). `attention` follows the spec
/// §6 attention-bit derivation: any pr_review row created/updated into
/// `{review requested, re-review requested}`, or any to_update flipping
/// status into `{changes requested, approved, review received, re-review requested}`.
public struct ApplyDiffResult: Equatable, Sendable {
    public var changes: Int
    public var attention: Bool

    public init(changes: Int = 0, attention: Bool = false) {
        self.changes = changes
        self.attention = attention
    }
}

// MARK: - Constants (mirror Python `db.py` and `syncer.py`)

/// Statuses that mean "do not surface in the active list" — see
/// `db.TERMINAL_STATUSES` (`db.py:7`). Mirrored locally because the sync
/// layer needs the same set without taking a dependency on the store internals.
private let terminalStatuses: Set<String> = ["merged", "closed", "done"]

/// Statuses that earn the attention bit when a NEW pr_review row enters the
/// store (or an existing pr_review row gains them via the create-race path).
/// See spec §6 rule 1 / `syncer.py:373-376`.
private let newReviewAttentionStatuses: Set<String> = [
    "review requested",
    "re-review requested"
]

/// Statuses that earn the attention bit when an UPDATE flips `status` into them.
/// See spec §6 rule 2 / `syncer.py:380-385`.
private let updateAttentionStatuses: Set<String> = [
    "changes requested",
    "approved",
    "review received",
    "re-review requested"
]

// MARK: - Apply

/// Faithful port of `syncer.py:337-395` (`run_sync`'s apply phase).
///
/// Walks the three diff buckets in order, writing through `store`, and tallies
/// `(changes, attention)`. A single `now` timestamp is shared across every
/// write in the cycle (matches `syncer.py:340` — `now = datetime.utcnow().isoformat()`
/// computed once before the apply loop). The notification-overlay attention
/// bit (spec §6 rule 3) is intentionally NOT covered here — that overlay is
/// dropped from the MVP per spec §10 / 2026-05-10 cut.
///
/// - Parameters:
///   - diff: Output of `diffTasks` for this sync cycle.
///   - store: Sync writer (production: `TaskStore`; tests: in-memory fake).
///   - now: Single shared timestamp string for all writes; default is
///         "now" formatted with the Python-compatible isoformat. Pass an
///         explicit value in tests for deterministic assertions.
public func applyDiff(
    _ diff: SyncDiff,
    store: SyncTaskWriter,
    now: String = defaultSyncTimestamp()
) async throws -> ApplyDiffResult {
    var result = ApplyDiffResult()

    // -- to_create (`syncer.py:343-378`) --
    for item in diff.toCreate {
        if terminalStatuses.contains(item.status) {
            // Bare merged/closed/done payload. Don't create a row in a
            // terminal state — only flip an existing matching row, if any.
            if let existingID = try await store.findTaskID(forGHURL: item.ghURL) {
                try await store.applySyncUpdate(
                    id: existingID,
                    title: nil,
                    source: nil,
                    status: item.status,
                    project: nil,
                    ghRepo: nil,
                    ghNumber: nil,
                    ghAuthor: nil,
                    ghAuthorName: nil,
                    tags: nil,
                    resetSeen: false,
                    now: now
                )
                result.changes += 1
            }
            // No matching row → silently skip (Python does the same).
            continue
        }

        if let existingID = try await store.findTaskID(forGHURL: item.ghURL) {
            // Race window: a row appeared at this gh_url since `getActiveTasks`
            // ran. Apply the syncer-spec §3.I "fixed allow-list" merge:
            // {title, source, status, project, gh_repo, gh_number, gh_author,
            //  gh_author_name, tags} where the incoming value is non-nil,
            // plus seen=0 and last_changed_at=now.
            try await store.applySyncUpdate(
                id: existingID,
                title: item.title,           // always present on a non-terminal create
                source: item.source,         // always present
                status: item.status,         // always present
                project: item.project,       // optional → only writes if non-nil
                ghRepo: item.ghRepo,
                ghNumber: item.ghNumber,
                ghAuthor: item.ghAuthor,
                ghAuthorName: item.ghAuthorName,
                tags: item.tags,
                resetSeen: true,
                now: now
            )
            result.changes += 1
        } else {
            try await store.insertSyncedTask(
                title: item.title,
                source: item.source,
                status: item.status,
                ghURL: item.ghURL,
                ghRepo: item.ghRepo,
                ghNumber: item.ghNumber,
                ghAuthor: item.ghAuthor,
                ghAuthorName: item.ghAuthorName,
                project: item.project,
                tags: item.tags,
                now: now
            )
            result.changes += 1
        }

        // Attention rule §6.1: new (or race-merged) pr_review at a
        // review-requesting status earns the attention bit.
        if item.source == "pr_review",
           newReviewAttentionStatuses.contains(item.status) {
            result.attention = true
        }
    }

    // -- to_update (`syncer.py:379-388`) --
    for patch in diff.toUpdate {
        try await store.applySyncUpdate(
            id: patch.id,
            title: patch.title,
            source: patch.source,
            status: patch.status,
            project: patch.project,
            ghRepo: nil,             // not in the diff comparison; not written
            ghNumber: nil,           // not in the diff comparison; not written
            ghAuthor: patch.ghAuthor,
            ghAuthorName: patch.ghAuthorName,
            tags: patch.tags,
            resetSeen: true,
            now: now
        )
        result.changes += 1

        // Attention rule §6.2: an UPDATE that flips `status` into the watched
        // set earns the attention bit. Status presence in the patch ⇔ Python's
        // `"status" in changes_dict` (the diff already gates on `old != new`).
        if let newStatus = patch.status,
           updateAttentionStatuses.contains(newStatus) {
            result.attention = true
        }
    }

    // -- to_close (`syncer.py:389-395`) --
    for task in diff.toClose {
        let terminal = terminalStatusForClose(source: task.source)
        try await store.applySyncUpdate(
            id: task.id,
            title: nil,
            source: nil,
            status: terminal,
            project: nil,
            ghRepo: nil,
            ghNumber: nil,
            ghAuthor: nil,
            ghAuthorName: nil,
            tags: nil,
            resetSeen: false,        // closed rows aren't user-actionable
            now: now
        )
        result.changes += 1
    }

    return result
}

/// Maps a closed row's `source` to its terminal status. Mirrors the
/// branch in `syncer.py:389-394`.
private func terminalStatusForClose(source: String) -> String {
    switch source {
    case "pr_authored": return "merged"
    case "pr_review": return "done"
    default: return "closed"
    }
}

// MARK: - Timestamp helper

/// Python-compatible isoformat (`yyyy-MM-dd'T'HH:mm:ss.SSSSSS+00:00`) for the
/// "single shared `now`" the apply phase stamps onto every row. Matches the
/// formatter `TaskStore` uses for its own writes so Swift- and Python-written
/// rows lex-sort together.
public func defaultSyncTimestamp(date: Date = Date()) -> String {
    syncTimestampFormatter.string(from: date)
}

private let syncTimestampFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(secondsFromGMT: 0)
    f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS'+00:00'"
    return f
}()
