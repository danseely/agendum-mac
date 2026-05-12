import Foundation
import Testing
@testable import AgendumSync

// MARK: - Fake writer

/// Records every call applyDiff makes. Each fake op carries the `now` it
/// received so tests can assert "single shared `now` across the whole cycle"
/// (syncer-spec §3.I).
private actor FakeWriter: SyncTaskWriter {
    enum Op: Equatable {
        case insert(Insert)
        case update(Update)
    }

    struct Insert: Equatable {
        var title: String
        var source: String
        var status: String
        var ghURL: String?
        var ghRepo: String?
        var ghNumber: Int?
        var ghAuthor: String?
        var ghAuthorName: String?
        var project: String?
        var tags: String?
        var now: String
    }

    struct Update: Equatable {
        var id: Int
        var title: String?
        var source: String?
        var status: String?
        var project: String?
        var ghRepo: String?
        var ghNumber: Int?
        var ghAuthor: String?
        var ghAuthorName: String?
        var tags: String?
        var changedColumns: Set<String>
        var resetSeen: Bool
        var now: String
    }

    private(set) var ops: [Op] = []
    /// Maps gh_url → existing row id. Configured per-test before applyDiff.
    private var existingIDsByURL: [String: Int]
    /// Auto-incrementing id source for inserts.
    private var nextInsertID: Int

    init(existingIDsByURL: [String: Int] = [:], nextInsertID: Int = 1000) {
        self.existingIDsByURL = existingIDsByURL
        self.nextInsertID = nextInsertID
    }

    func findTaskID(forGHURL ghURL: String) async throws -> Int? {
        existingIDsByURL[ghURL]
    }

    @discardableResult
    func insertSyncedTask(
        title: String, source: String, status: String,
        ghURL: String?, ghRepo: String?, ghNumber: Int?,
        ghAuthor: String?, ghAuthorName: String?,
        project: String?, tags: String?, now: String
    ) async throws -> Int {
        ops.append(.insert(.init(
            title: title, source: source, status: status,
            ghURL: ghURL, ghRepo: ghRepo, ghNumber: ghNumber,
            ghAuthor: ghAuthor, ghAuthorName: ghAuthorName,
            project: project, tags: tags, now: now
        )))
        let id = nextInsertID
        nextInsertID += 1
        if let url = ghURL { existingIDsByURL[url] = id }
        return id
    }

    func applySyncUpdate(
        id: Int, title: String?, source: String?, status: String?,
        project: String?, ghRepo: String?, ghNumber: Int?,
        ghAuthor: String?, ghAuthorName: String?, tags: String?,
        changedColumns: Set<String>, resetSeen: Bool, now: String
    ) async throws {
        ops.append(.update(.init(
            id: id, title: title, source: source, status: status,
            project: project, ghRepo: ghRepo, ghNumber: ghNumber,
            ghAuthor: ghAuthor, ghAuthorName: ghAuthorName, tags: tags,
            changedColumns: changedColumns, resetSeen: resetSeen, now: now
        )))
    }

    func recordedOps() -> [Op] { ops }
}

// MARK: - Helpers

private let fixedNow = "2026-05-11T12:00:00.000000+00:00"

private func incoming(
    title: String = "T",
    source: String = "pr_authored",
    status: String = "open",
    ghURL: String,
    ghNumber: Int? = 1,
    ghRepo: String? = "octo/repo",
    project: String? = nil,
    ghAuthor: String? = nil,
    ghAuthorName: String? = nil,
    tags: String? = nil,
    presentFields: Set<IncomingTask.Field> = []
) -> IncomingTask {
    IncomingTask(
        title: title, source: source, status: status, ghURL: ghURL,
        ghNumber: ghNumber, ghRepo: ghRepo, project: project,
        ghAuthor: ghAuthor, ghAuthorName: ghAuthorName, tags: tags,
        presentFields: presentFields
    )
}

private func existing(
    id: Int, ghURL: String?, source: String = "pr_authored",
    status: String = "open", title: String = "T", ghRepo: String? = "octo/repo"
) -> ExistingTask {
    ExistingTask(
        id: id, title: title, source: source, status: status,
        ghURL: ghURL, ghRepo: ghRepo
    )
}

// MARK: - Tests

@Suite struct ApplyDiffTests {

    @Test func toCreateInsertsBrandNewRowWithNowStamp() async throws {
        let writer = FakeWriter()
        let item = incoming(
            title: "Add login", source: "pr_authored", status: "open",
            ghURL: "https://github.com/octo/repo/pull/1",
            ghNumber: 1, ghRepo: "octo/repo",
            ghAuthor: "alice", ghAuthorName: "Alice",
            tags: #"["bug"]"#
        )
        let diff = SyncDiff(toCreate: [item])

        let result = try await applyDiff(diff, store: writer, now: fixedNow)

        #expect(result.changes == 1)
        #expect(result.attention == false)
        let ops = await writer.recordedOps()
        #expect(ops.count == 1)
        guard case .insert(let ins) = ops[0] else {
            Issue.record("expected insert"); return
        }
        #expect(ins.title == "Add login")
        #expect(ins.source == "pr_authored")
        #expect(ins.status == "open")
        #expect(ins.ghURL == "https://github.com/octo/repo/pull/1")
        #expect(ins.ghNumber == 1)
        #expect(ins.ghRepo == "octo/repo")
        #expect(ins.ghAuthor == "alice")
        #expect(ins.ghAuthorName == "Alice")
        #expect(ins.tags == #"["bug"]"#)
        #expect(ins.now == fixedNow)
    }

    @Test func toCreateWithTerminalStatusAndNoExistingRowSkips() async throws {
        // Bare merged payload, gh_url not in store → never insert a row in a
        // terminal state. Spec §3.I bullet 1.
        let writer = FakeWriter()
        let diff = SyncDiff(toCreate: [
            incoming(
                title: "", status: "merged",
                ghURL: "https://github.com/octo/repo/pull/2"
            )
        ])

        let result = try await applyDiff(diff, store: writer, now: fixedNow)

        #expect(result.changes == 0)
        #expect(result.attention == false)
        let ops = await writer.recordedOps()
        #expect(ops.isEmpty)
    }

    @Test func toCreateWithTerminalStatusFlipsExistingRow() async throws {
        // Bare merged payload, row already exists at gh_url → write only the
        // terminal status; don't reset seen, don't touch other columns.
        let writer = FakeWriter(
            existingIDsByURL: ["https://github.com/octo/repo/pull/3": 42]
        )
        let diff = SyncDiff(toCreate: [
            incoming(
                title: "", status: "merged",
                ghURL: "https://github.com/octo/repo/pull/3"
            )
        ])

        let result = try await applyDiff(diff, store: writer, now: fixedNow)

        #expect(result.changes == 1)
        #expect(result.attention == false)
        let ops = await writer.recordedOps()
        #expect(ops.count == 1)
        guard case .update(let upd) = ops[0] else {
            Issue.record("expected update"); return
        }
        #expect(upd.id == 42)
        #expect(upd.status == "merged")
        #expect(upd.title == nil)        // bare payload → no title overwrite via this path
        #expect(upd.resetSeen == false)  // closed rows aren't user-actionable
        #expect(upd.now == fixedNow)
    }

    @Test func toCreateRaceMergesAllowListWithSeenReset() async throws {
        // Row appeared at this gh_url since getActiveTasks ran (race window).
        // Spec §3.I bullet 2: merge allow-list fields where incoming is not
        // nil, plus seen=0 and last_changed_at=now.
        let writer = FakeWriter(
            existingIDsByURL: ["https://github.com/octo/repo/pull/4": 7]
        )
        let item = incoming(
            title: "Race merge", source: "pr_review", status: "review requested",
            ghURL: "https://github.com/octo/repo/pull/4",
            ghNumber: 4, ghRepo: "octo/repo",
            project: nil,            // optional → must NOT be written
            ghAuthor: "bob", ghAuthorName: "Bob",
            tags: #"["review"]"#
        )
        let diff = SyncDiff(toCreate: [item])

        let result = try await applyDiff(diff, store: writer, now: fixedNow)

        #expect(result.changes == 1)
        #expect(result.attention == true) // pr_review + review requested
        let ops = await writer.recordedOps()
        guard case .update(let upd) = ops[0] else {
            Issue.record("expected update"); return
        }
        #expect(upd.id == 7)
        #expect(upd.title == "Race merge")
        #expect(upd.source == "pr_review")
        #expect(upd.status == "review requested")
        #expect(upd.project == nil)        // not written (incoming was nil)
        #expect(upd.ghRepo == "octo/repo")
        #expect(upd.ghNumber == 4)
        #expect(upd.ghAuthor == "bob")
        #expect(upd.ghAuthorName == "Bob")
        #expect(upd.tags == #"["review"]"#)
        #expect(upd.resetSeen == true)
        #expect(upd.now == fixedNow)
    }

    @Test func toCreateAttentionForReviewRequestedNewPRReview() async throws {
        let writer = FakeWriter()
        let diff = SyncDiff(toCreate: [
            incoming(source: "pr_review", status: "review requested",
                     ghURL: "https://x/pr/1")
        ])
        let result = try await applyDiff(diff, store: writer, now: fixedNow)
        #expect(result.attention == true)
    }

    @Test func toCreateAttentionForReReviewRequestedNewPRReview() async throws {
        let writer = FakeWriter()
        let diff = SyncDiff(toCreate: [
            incoming(source: "pr_review", status: "re-review requested",
                     ghURL: "https://x/pr/2")
        ])
        let result = try await applyDiff(diff, store: writer, now: fixedNow)
        #expect(result.attention == true)
    }

    @Test func toCreateNoAttentionForNonPRReviewSource() async throws {
        let writer = FakeWriter()
        let diff = SyncDiff(toCreate: [
            // Same status string, but source is not pr_review → no attention.
            incoming(source: "pr_authored", status: "review requested",
                     ghURL: "https://x/pr/3")
        ])
        let result = try await applyDiff(diff, store: writer, now: fixedNow)
        #expect(result.attention == false)
    }

    @Test func toUpdateAppliesPatchWithSeenResetAndAlwaysBumpsUpdatedAt() async throws {
        let writer = FakeWriter()
        let patch = UpdatePatch(
            id: 11,
            title: "New title",
            status: "approved",
            ghAuthor: "carol"
            // project, source, ghAuthorName, tags left nil → not written
        )
        let diff = SyncDiff(toUpdate: [patch])

        let result = try await applyDiff(diff, store: writer, now: fixedNow)

        #expect(result.changes == 1)
        #expect(result.attention == true) // approved ∈ updateAttentionStatuses
        let ops = await writer.recordedOps()
        guard case .update(let upd) = ops[0] else {
            Issue.record("expected update"); return
        }
        #expect(upd.id == 11)
        #expect(upd.title == "New title")
        #expect(upd.status == "approved")
        #expect(upd.ghAuthor == "carol")
        #expect(upd.changedColumns == ["title", "status", "gh_author"])
        #expect(upd.source == nil)
        #expect(upd.project == nil)
        #expect(upd.ghAuthorName == nil)
        #expect(upd.tags == nil)
        #expect(upd.ghRepo == nil)        // not in to_update bucket per spec
        #expect(upd.ghNumber == nil)
        #expect(upd.resetSeen == true)
        #expect(upd.now == fixedNow)
    }

    @Test func toUpdateCanWriteExplicitNullForOptionalColumns() async throws {
        let writer = FakeWriter()
        let patch = UpdatePatch(
            id: 12,
            ghAuthor: nil,
            ghAuthorName: nil,
            tags: nil,
            changedFields: [.ghAuthor, .ghAuthorName, .tags]
        )
        let diff = SyncDiff(toUpdate: [patch])

        let result = try await applyDiff(diff, store: writer, now: fixedNow)

        #expect(result.changes == 1)
        let ops = await writer.recordedOps()
        guard case .update(let upd) = ops[0] else {
            Issue.record("expected update"); return
        }
        #expect(upd.ghAuthor == nil)
        #expect(upd.ghAuthorName == nil)
        #expect(upd.tags == nil)
        #expect(upd.changedColumns == ["gh_author", "gh_author_name", "tags"])
        #expect(upd.resetSeen == true)
    }

    @Test func toUpdateAttentionFiresForEachWatchedStatus() async throws {
        // Each of the four status strings independently flips attention.
        for status in ["changes requested", "approved", "review received", "re-review requested"] {
            let writer = FakeWriter()
            let diff = SyncDiff(toUpdate: [UpdatePatch(id: 1, status: status)])
            let result = try await applyDiff(diff, store: writer, now: fixedNow)
            #expect(result.attention == true, "status \(status) should flip attention")
        }
    }

    @Test func toUpdateNoAttentionWhenStatusNotInWatchedSet() async throws {
        let writer = FakeWriter()
        let diff = SyncDiff(toUpdate: [
            UpdatePatch(id: 1, status: "open"),
            UpdatePatch(id: 2, title: "renamed only")  // no status change at all
        ])
        let result = try await applyDiff(diff, store: writer, now: fixedNow)
        #expect(result.changes == 2)
        #expect(result.attention == false)
    }

    @Test func toCloseUsesMergedForAuthoredPRs() async throws {
        let writer = FakeWriter()
        let diff = SyncDiff(toClose: [
            existing(id: 1, ghURL: "https://x/pr/1", source: "pr_authored")
        ])
        let result = try await applyDiff(diff, store: writer, now: fixedNow)
        #expect(result.changes == 1)
        #expect(result.attention == false)
        let ops = await writer.recordedOps()
        guard case .update(let upd) = ops[0] else {
            Issue.record("expected update"); return
        }
        #expect(upd.id == 1)
        #expect(upd.status == "merged")
        #expect(upd.resetSeen == false)
    }

    @Test func toCloseUsesDoneForReviewRequests() async throws {
        let writer = FakeWriter()
        let diff = SyncDiff(toClose: [
            existing(id: 2, ghURL: "https://x/pr/2", source: "pr_review")
        ])
        _ = try await applyDiff(diff, store: writer, now: fixedNow)
        let ops = await writer.recordedOps()
        guard case .update(let upd) = ops[0] else {
            Issue.record("expected update"); return
        }
        #expect(upd.status == "done")
    }

    @Test func toCloseUsesClosedForOtherSources() async throws {
        let writer = FakeWriter()
        let diff = SyncDiff(toClose: [
            existing(id: 3, ghURL: "https://x/issue/9", source: "issue")
        ])
        _ = try await applyDiff(diff, store: writer, now: fixedNow)
        let ops = await writer.recordedOps()
        guard case .update(let upd) = ops[0] else {
            Issue.record("expected update"); return
        }
        #expect(upd.status == "closed")
    }

    @Test func nowIsSharedAcrossEveryWriteInTheCycle() async throws {
        // Single shared `now` across all three buckets — syncer.py:340.
        let writer = FakeWriter(
            existingIDsByURL: ["https://x/pr/race": 99]
        )
        let diff = SyncDiff(
            toCreate: [
                incoming(ghURL: "https://x/pr/new"),
                incoming(ghURL: "https://x/pr/race")  // race-merge path
            ],
            toUpdate: [UpdatePatch(id: 5, status: "approved")],
            toClose: [existing(id: 6, ghURL: "https://x/pr/gone")]
        )

        let result = try await applyDiff(diff, store: writer, now: fixedNow)

        #expect(result.changes == 4)
        let ops = await writer.recordedOps()
        for op in ops {
            switch op {
            case .insert(let ins): #expect(ins.now == fixedNow)
            case .update(let upd): #expect(upd.now == fixedNow)
            }
        }
    }

    @Test func emptyDiffYieldsZeroChangesAndNoAttention() async throws {
        let writer = FakeWriter()
        let result = try await applyDiff(SyncDiff(), store: writer, now: fixedNow)
        #expect(result == ApplyDiffResult(changes: 0, attention: false))
        let ops = await writer.recordedOps()
        #expect(ops.isEmpty)
    }

    @Test func defaultSyncTimestampMatchesPythonISOFormat() {
        // Sanity check: the formatter emits the +00:00 microsecond shape that
        // sorts lex-correctly against Python-written timestamps.
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let stamped = defaultSyncTimestamp(date: date)
        #expect(stamped.hasSuffix("+00:00"))
        #expect(stamped.contains("T"))
        // Microsecond precision: 6 digits of fraction.
        let parts = stamped.split(separator: ".")
        #expect(parts.count == 2)
        let frac = parts[1].prefix { $0.isNumber }
        #expect(frac.count == 6)
    }
}
