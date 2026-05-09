@testable import AgendumMacStore
import AgendumFeature
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
    seen: Int? = 1,
    lastChangedAt: String? = "2026-05-09T00:00:00+00:00",
    createdAt: String? = "2026-05-09T00:00:00+00:00",
    updatedAt: String? = "2026-05-09T00:00:00+00:00"
) async throws {
    try await store.insertRaw(
        id: id, title: title, source: source, status: status, seen: seen,
        lastChangedAt: lastChangedAt, createdAt: createdAt, updatedAt: updatedAt
    )
}
