@testable import AgendumMacStore
import AgendumFeature
import Foundation
import GRDB
import Testing

struct TaskStoreTests {
    @Test
    func tasksReturnsInsertedTask() async throws {
        let store = try TaskStore()
        try await insertTask(store, id: 1, title: "Review PR", source: "pr_review")

        let items = try await store.tasks(matching: .default)

        #expect(items.count == 1)
        #expect(items[0].id == 1)
        #expect(items[0].title == "Review PR")
        #expect(items[0].source == .review)
    }

    @Test
    func tasksFiltersToMatchingSource() async throws {
        let store = try TaskStore()
        try await insertTask(store, id: 1, title: "Open issue", source: "issue")
        try await insertTask(store, id: 2, title: "Review PR", source: "pr_review")

        let items = try await store.tasks(matching: TaskListFilters(source: "issue"))

        #expect(items.count == 1)
        #expect(items[0].source == .issues)
    }

    @Test
    func tasksFiltersToMatchingStatus() async throws {
        let store = try TaskStore()
        try await insertTask(store, id: 1, title: "Backlog task", source: "manual", status: "backlog")
        try await insertTask(store, id: 2, title: "In progress task", source: "manual", status: "in progress")

        let items = try await store.tasks(matching: TaskListFilters(status: "backlog"))

        #expect(items.count == 1)
        #expect(items[0].title == "Backlog task")
    }

    @Test
    func tasksExcludesSeenWhenFilterDisabled() async throws {
        let store = try TaskStore()
        try await insertTask(store, id: 1, title: "Seen task", source: "manual", seen: 1)
        try await insertTask(store, id: 2, title: "Unseen task", source: "manual", seen: 0)

        let items = try await store.tasks(matching: TaskListFilters(includeSeen: false))

        #expect(items.count == 1)
        #expect(items[0].title == "Unseen task")
        #expect(items[0].isUnseen)
    }

    @Test
    func tasksIncludesNullSeenWhenFilterDisabled() async throws {
        let store = try TaskStore()
        try await insertRawTask(store, id: 1, title: "Null seen task", source: "manual", seen: nil)

        let items = try await store.tasks(matching: TaskListFilters(includeSeen: false))

        #expect(items.count == 1)
        #expect(items[0].isUnseen)
    }

    @Test
    func tasksMapLegacyNullableTimestampsGracefully() async throws {
        let store = try TaskStore()
        try await insertRawTask(store, id: 1, title: "Legacy task", source: "manual",
                                lastChangedAt: nil, createdAt: nil, updatedAt: nil)

        let items = try await store.tasks(matching: .default)

        #expect(items.count == 1)
        #expect(items[0].title == "Legacy task")
    }

    @Test
    func taskLookupByIDReturnsMatchingItem() async throws {
        let store = try TaskStore()
        try await insertTask(store, id: 1, title: "Found task", source: "manual")
        try await insertTask(store, id: 2, title: "Other task", source: "manual")

        let item = try await store.task(id: 1)

        #expect(item?.title == "Found task")
    }

    @Test
    func taskLookupByIDReturnsNilForMissingID() async throws {
        let store = try TaskStore()

        let item = try await store.task(id: 99)

        #expect(item == nil)
    }

    @Test
    func markSeenSetsSeenAndTimestamps() async throws {
        let store = try TaskStore()
        try await insertTask(store, id: 1, title: "Unseen task", source: "manual", seen: 0)

        #expect((try await store.task(id: 1))?.isUnseen == true)

        try await store.markSeen(id: 1)

        let item = try await store.task(id: 1)
        #expect(item?.isUnseen == false)

        let record = try await store.rawRecord(id: 1)
        #expect(record?.lastSeenAt != nil)
        #expect(record?.updatedAt != nil)
        // updatedAt should differ from the original "2026-05-09T00:00:00+00:00" fixture value
        #expect(record?.updatedAt != "2026-05-09T00:00:00+00:00")
    }

    @Test
    func tasksExcludesTerminalStatusesByDefault() async throws {
        let store = try TaskStore()
        try await insertTask(store, id: 1, title: "Open task", source: "manual", status: "backlog")
        try await insertTask(store, id: 2, title: "Merged PR", source: "pr_authored", status: "merged")
        try await insertTask(store, id: 3, title: "Closed issue", source: "issue", status: "closed")
        try await insertTask(store, id: 4, title: "Done manual", source: "manual", status: "done")
        try await insertTask(store, id: 5, title: "Review needed", source: "pr_review", status: "review requested")

        let items = try await store.tasks(matching: .default)

        #expect(items.map(\.id).sorted() == [1, 5])
    }

    @Test
    func tasksWithExplicitStatusFilterCanReturnTerminalRows() async throws {
        let store = try TaskStore()
        try await insertTask(store, id: 1, title: "Open task", source: "manual", status: "backlog")
        try await insertTask(store, id: 2, title: "Merged PR", source: "pr_authored", status: "merged")

        // Explicit status filter takes precedence and bypasses the default exclusion
        let items = try await store.tasks(matching: TaskListFilters(status: "merged"))

        #expect(items.count == 1)
        #expect(items[0].title == "Merged PR")
    }

    @Test
    func markSeenTimestampMatchesPythonISOFormat() async throws {
        let store = try TaskStore()
        try await insertTask(store, id: 1, title: "T", source: "manual", seen: 0)

        try await store.markSeen(id: 1)

        let record = try await store.rawRecord(id: 1)
        let updatedAt = try #require(record?.updatedAt)
        // Match Python datetime.now(timezone.utc).isoformat():
        // YYYY-MM-DDTHH:MM:SS.ffffff+00:00 — fractional seconds + +00:00 suffix
        // (not the ISO8601DateFormatter default of `Z`)
        #expect(updatedAt.hasSuffix("+00:00"))
        #expect(!updatedAt.hasSuffix("Z"))
        // Confirm fractional seconds are present (6 digits after the dot)
        #expect(updatedAt.range(of: #"\.\d{6}\+00:00$"#, options: .regularExpression) != nil)
    }

    @Test
    func markSeenWithNonExistentIDSucceedsSilently() async throws {
        let store = try TaskStore()
        // Protocol contract: silent no-op when id is not found
        try await store.markSeen(id: 999)
    }

    @Test
    func updateTaskStatusFlipsStatusAndBumpsUpdatedAt() async throws {
        let store = try TaskStore()
        try await insertTask(store, id: 1, title: "T", source: "manual", status: "backlog")
        let originalUpdatedAt = try await store.rawRecord(id: 1)?.updatedAt

        try await store.updateTaskStatus(id: 1, status: "in progress")

        let item = try await store.task(id: 1)
        #expect(item?.status == "in progress")
        let record = try await store.rawRecord(id: 1)
        #expect(record?.updatedAt != originalUpdatedAt)
        #expect(record?.updatedAt?.range(of: #"\.\d{6}\+00:00$"#, options: .regularExpression) != nil)
    }

    @Test
    func updateTaskStatusWithNonExistentIDSucceedsSilently() async throws {
        let store = try TaskStore()
        try await store.updateTaskStatus(id: 999, status: "done")
    }

    @Test
    func removeTaskDeletesRow() async throws {
        let store = try TaskStore()
        try await insertTask(store, id: 1, title: "T", source: "manual")
        try await insertTask(store, id: 2, title: "Other", source: "manual")

        try await store.removeTask(id: 1)

        #expect(try await store.task(id: 1) == nil)
        let remaining = try await store.tasks(matching: .default)
        #expect(remaining.map(\.id) == [2])
    }

    @Test
    func removeTaskWithNonExistentIDSucceedsSilently() async throws {
        let store = try TaskStore()
        try await store.removeTask(id: 999)
    }

    @Test
    func createManualTaskInsertsBacklogManualRow() async throws {
        let store = try TaskStore()

        let created = try await store.createManualTask(title: "Buy milk", project: "Errands", tags: ["home", "shopping"])

        #expect(created.title == "Buy milk")
        #expect(created.source == .manual)
        #expect(created.backendSource == "manual")
        #expect(created.status == "backlog")
        #expect(created.project == "Errands")
        // Manual tasks default to seen=1 per schema (user-created, not a notification).
        // Matches Python `add_task` behavior.
        #expect(!created.isUnseen)
        let stored = try await store.rawRecord(id: Int64(created.id))
        #expect(stored?.tags == #"["home","shopping"]"#)
    }

    @Test
    func createManualTaskTrimsTitleAndRejectsEmpty() async throws {
        let store = try TaskStore()

        let trimmed = try await store.createManualTask(title: "  Padded  ", project: nil, tags: nil)
        #expect(trimmed.title == "Padded")

        await #expect(throws: TaskStoreError.invalidInput("title must not be empty")) {
            try await store.createManualTask(title: "   ", project: nil, tags: nil)
        }
    }

    @Test
    func searchTasksReturnsTokenAndMatches() async throws {
        let store = try TaskStore()
        try await insertTask(store, id: 1, title: "Review release dashboard PR", source: "pr_review", status: "review requested")
        try await insertTask(store, id: 2, title: "Buy milk", source: "manual")
        try await insertTask(store, id: 3, title: "Audit dashboard widget tests", source: "issue", status: "open")

        let results = try await store.searchTasks(query: "dashboard review", source: nil, status: nil, project: nil, limit: 10)

        // Token-AND: must contain both "dashboard" and "review"
        #expect(results.count == 1)
        #expect(results[0].id == 1)
    }

    @Test
    func searchTasksRequiresNonEmptyQuery() async throws {
        let store = try TaskStore()
        await #expect(throws: TaskStoreError.invalidInput("query must not be empty")) {
            try await store.searchTasks(query: "   ", source: nil, status: nil, project: nil, limit: 10)
        }
    }

    @Test
    func searchTasksMatchesGhRepoTagsAndAuthorFromRecord() async throws {
        // Verifies parity with Python `_task_haystack`: search reaches fields that
        // `TaskItem` doesn't carry (`gh_repo`, `tags`, `gh_url`, `gh_author_name`).
        let store = try TaskStore()
        try await store.insert(TaskRecord(
            id: 1, title: "PR title",
            source: "pr_authored", status: "open",
            project: "agendum-mac", ghRepo: "danseely/agendum-mac",
            ghURL: "https://github.com/danseely/agendum-mac/pull/42",
            ghAuthor: "danseely", ghAuthorName: "Dan",
            tags: #"["bug","release"]"#, seen: 1,
            lastChangedAt: "2026-05-09T00:00:00.000000+00:00",
            createdAt: "2026-05-09T00:00:00.000000+00:00",
            updatedAt: "2026-05-09T00:00:00.000000+00:00"
        ))

        // Match by gh_repo full owner/name
        let byRepo = try await store.searchTasks(query: "danseely/agendum-mac", source: nil, status: nil, project: nil, limit: 10)
        #expect(byRepo.count == 1)
        // Match by tag
        let byTag = try await store.searchTasks(query: "release", source: nil, status: nil, project: nil, limit: 10)
        #expect(byTag.count == 1)
        // Match by gh_author_name (display name, not login)
        let byName = try await store.searchTasks(query: "Dan", source: nil, status: nil, project: nil, limit: 10)
        #expect(byName.count == 1)
    }

    @Test
    func taskStoreCreatesParentDirectory() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("agendum-store-test-\(UUID().uuidString)")
        let dbURL = tmp.appendingPathComponent("nested").appendingPathComponent("agendum.db")
        defer { try? FileManager.default.removeItem(at: tmp) }

        // Parent dir does not exist yet — TaskStore should create it.
        #expect(!FileManager.default.fileExists(atPath: dbURL.deletingLastPathComponent().path))

        _ = try TaskStore(path: dbURL)

        #expect(FileManager.default.fileExists(atPath: dbURL.path))
        #expect(FileManager.default.fileExists(atPath: dbURL.deletingLastPathComponent().path))
    }

    @Test
    func tasksOrdersUnseenBeforeSeenThenByUpdatedAt() async throws {
        let store = try TaskStore()
        // Insert seen task with older updated_at
        try await insertRawTask(store, id: 1, title: "Seen older", source: "manual",
                                seen: 1, updatedAt: "2026-05-01T00:00:00+00:00")
        // Insert unseen task with newer updated_at
        try await insertRawTask(store, id: 2, title: "Unseen newer", source: "manual",
                                seen: 0, updatedAt: "2026-05-09T00:00:00+00:00")
        // Insert unseen task with older updated_at
        try await insertRawTask(store, id: 3, title: "Unseen older", source: "manual",
                                seen: 0, updatedAt: "2026-05-05T00:00:00+00:00")

        let items = try await store.tasks(matching: .default)

        // Unseen tasks first (seen ASC), then seen; within each group by updated_at DESC
        #expect(items.map(\.id) == [2, 3, 1])
    }

    @Test
    func tasksRespectsLimit() async throws {
        let store = try TaskStore()
        for i in 1...5 {
            try await insertTask(store, id: Int64(i), title: "Task \(i)", source: "manual")
        }

        let items = try await store.tasks(matching: TaskListFilters(limit: 3))

        #expect(items.count == 3)
    }

    @Test
    func observeEmitsNewTaskInsertedAfterSubscription() async throws {
        let store = try TaskStore()

        let stream = store.observe(matching: .default)
        var iterator = stream.makeAsyncIterator()

        // First emission: empty
        let initial = await iterator.next()
        #expect(initial?.isEmpty == true)

        // Insert after subscribing
        try await insertTask(store, id: 1, title: "Late arrival", source: "manual")

        let updated = await iterator.next()
        #expect(updated?.count == 1)
        #expect(updated?.first?.title == "Late arrival")
    }

    @Test
    func observeYieldsCurrentTasksOnSubscription() async throws {
        let store = try TaskStore()
        try await insertTask(store, id: 1, title: "Watch me", source: "manual")

        let stream = store.observe(matching: .default)
        var iterator = stream.makeAsyncIterator()
        let items = await iterator.next()

        #expect(items?.count == 1)
        #expect(items?.first?.title == "Watch me")
    }

    @Test
    func observeEmitsUpdatedValueAfterChange() async throws {
        let store = try TaskStore()
        try await insertTask(store, id: 1, title: "Before", source: "manual", seen: 0)

        let stream = store.observe(matching: TaskListFilters(includeSeen: false))
        var iterator = stream.makeAsyncIterator()

        // First emission: unseen task is present
        let initial = await iterator.next()
        #expect(initial?.count == 1)

        // Mark seen → task drops out of the unseen filter
        try await store.markSeen(id: 1)

        let updated = await iterator.next()
        #expect(updated?.isEmpty == true)
    }
}

// MARK: - Helpers

private func insertTask(
    _ store: TaskStore,
    id: Int64,
    title: String,
    source: String,
    status: String = "backlog",
    seen: Int? = 0
) async throws {
    let record = TaskRecord(
        id: id,
        title: title,
        source: source,
        status: status,
        seen: seen,
        lastChangedAt: "2026-05-09T00:00:00+00:00",
        createdAt: "2026-05-09T00:00:00+00:00",
        updatedAt: "2026-05-09T00:00:00+00:00"
    )
    try await store.insert(record)
}

private func insertRawTask(
    _ store: TaskStore,
    id: Int64,
    title: String,
    source: String,
    status: String = "backlog",
    seen: Int? = 0,
    lastChangedAt: String? = "2026-05-09T00:00:00+00:00",
    createdAt: String? = "2026-05-09T00:00:00+00:00",
    updatedAt: String? = "2026-05-09T00:00:00+00:00"
) async throws {
    try await store.insertRaw(
        id: id, title: title, source: source, status: status, seen: seen,
        lastChangedAt: lastChangedAt, createdAt: createdAt, updatedAt: updatedAt
    )
}
