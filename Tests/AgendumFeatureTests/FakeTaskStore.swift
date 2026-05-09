import AgendumFeature
import Testing

actor FakeTaskStore: TaskStoreProviding {
    private var storedTasks: [TaskItem] = []

    func setTasks(_ tasks: [TaskItem]) {
        storedTasks = tasks
    }

    func tasks(matching filters: TaskListFilters) async throws -> [TaskItem] {
        storedTasks
    }

    // TODO: C3 — emit storedTasks as initial value and re-emit on setTasks(_:) so
    // workflow model tests can exercise live observation.
    nonisolated func observe(matching filters: TaskListFilters) -> AsyncStream<[TaskItem]> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    func task(id: TaskItem.ID) async throws -> TaskItem? {
        storedTasks.first { $0.id == id }
    }

    func markSeen(id: TaskItem.ID) async throws {
        storedTasks = storedTasks.map { task in
            guard task.id == id else { return task }
            return TaskItem(
                id: task.id,
                title: task.title,
                backendSource: task.backendSource,
                source: task.source,
                status: task.status,
                project: task.project,
                author: task.author,
                number: task.number,
                url: task.url,
                isUnseen: false
            )
        }
    }
}

// Minimal smoke test confirming FakeTaskStore satisfies TaskStoreProviding.
struct FakeTaskStoreTests {
    @Test
    func fakeStoreReturnsSeedTasks() async throws {
        let fake = FakeTaskStore()
        await fake.setTasks([
            TaskItem(
                id: 1,
                title: "Fake task",
                backendSource: "manual",
                source: .manual,
                status: "backlog",
                project: "Test",
                author: nil,
                number: nil,
                url: nil,
                isUnseen: true
            )
        ])

        let items = try await fake.tasks(matching: .default)

        #expect(items.count == 1)
        #expect(items[0].title == "Fake task")
        #expect(items[0].isUnseen)
    }

    @Test
    func fakeStoreMarkSeenClearsUnseenFlag() async throws {
        let fake = FakeTaskStore()
        await fake.setTasks([
            TaskItem(id: 1, title: "T", backendSource: "manual", source: .manual,
                     status: "backlog", project: "P", author: nil, number: nil, url: nil, isUnseen: true)
        ])

        try await fake.markSeen(id: 1)

        let item = try await fake.task(id: 1)
        #expect(item?.isUnseen == false)
    }
}
