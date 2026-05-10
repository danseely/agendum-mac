import AgendumFeature
import Testing

actor FakeTaskStore: TaskStoreProviding {
    private var storedTasks: [TaskItem] = []
    private(set) var operations: [Operation] = []
    private var nextManualID: Int = 10000

    enum Operation: Equatable {
        case markSeen(Int)
        case updateTaskStatus(id: Int, status: String)
        case removeTask(Int)
        case createManualTask(title: String, project: String?, tags: [String]?)
        case search(String)
    }

    func setTasks(_ tasks: [TaskItem]) {
        storedTasks = tasks
    }

    func tasks(matching filters: TaskListFilters) async throws -> [TaskItem] {
        applyFilters(filters, to: storedTasks)
    }

    /// Emits the current snapshot once on subscription, then finishes.
    /// Workflow tests that need re-emission should drive state explicitly.
    nonisolated func observe(matching filters: TaskListFilters) -> AsyncStream<[TaskItem]> {
        let (stream, continuation) = AsyncStream.makeStream(of: [TaskItem].self)
        Task {
            let snapshot = try? await tasks(matching: filters)
            continuation.yield(snapshot ?? [])
            continuation.finish()
        }
        return stream
    }

    func task(id: TaskItem.ID) async throws -> TaskItem? {
        storedTasks.first { $0.id == id }
    }

    func markSeen(id: TaskItem.ID) async throws {
        operations.append(.markSeen(id))
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

    func updateTaskStatus(id: TaskItem.ID, status: String) async throws {
        operations.append(.updateTaskStatus(id: id, status: status))
        storedTasks = storedTasks.map { task in
            guard task.id == id else { return task }
            return TaskItem(
                id: task.id,
                title: task.title,
                backendSource: task.backendSource,
                source: task.source,
                status: status,
                project: task.project,
                author: task.author,
                number: task.number,
                url: task.url,
                isUnseen: task.isUnseen
            )
        }
    }

    func removeTask(id: TaskItem.ID) async throws {
        operations.append(.removeTask(id))
        storedTasks.removeAll { $0.id == id }
    }

    @discardableResult
    func createManualTask(title: String, project: String?, tags: [String]?) async throws -> TaskItem {
        operations.append(.createManualTask(title: title, project: project, tags: tags))
        let id = nextManualID
        nextManualID += 1
        let item = TaskItem(
            id: id,
            title: title,
            backendSource: "manual",
            source: .manual,
            status: "backlog",
            project: project ?? "No project",
            author: nil,
            number: nil,
            url: nil,
            isUnseen: true
        )
        storedTasks.append(item)
        return item
    }

    func searchTasks(
        query: String,
        source: String?,
        status: String?,
        project: String?,
        limit: Int
    ) async throws -> [TaskItem] {
        operations.append(.search(query))
        let tokens = query
            .split(whereSeparator: { $0.isWhitespace })
            .map { String($0).lowercased() }
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return [] }
        let filtered = applyFilters(
            TaskListFilters(source: source, status: status, project: project, includeSeen: true, limit: 200),
            to: storedTasks
        )
        return filtered.filter { item in
            let hay = "\(item.title) \(item.project) \(item.backendSource) \(item.author ?? "")".lowercased()
            return tokens.allSatisfy { hay.contains($0) }
        }.prefix(max(1, min(limit, 200))).map { $0 }
    }

    func resetOperations() {
        operations = []
    }

    // MARK: - Private

    private func applyFilters(_ filters: TaskListFilters, to source: [TaskItem]) -> [TaskItem] {
        source.filter { task in
            if let s = filters.source, task.backendSource != s { return false }
            if let s = filters.status, task.status != s { return false }
            if let p = filters.project, task.project != p { return false }
            if !filters.includeSeen, !task.isUnseen { return false }
            return true
        }.prefix(max(1, min(filters.limit, 200))).map { $0 }
    }
}

// Minimal smoke tests confirming FakeTaskStore satisfies TaskStoreProviding.
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

    @Test
    func fakeStoreUpdateTaskStatusFlipsStatus() async throws {
        let fake = FakeTaskStore()
        await fake.setTasks([
            TaskItem(id: 1, title: "T", backendSource: "manual", source: .manual,
                     status: "backlog", project: "P", author: nil, number: nil, url: nil, isUnseen: true)
        ])

        try await fake.updateTaskStatus(id: 1, status: "in progress")

        let item = try await fake.task(id: 1)
        #expect(item?.status == "in progress")
    }

    @Test
    func fakeStoreRemoveTaskDropsRow() async throws {
        let fake = FakeTaskStore()
        await fake.setTasks([
            TaskItem(id: 1, title: "T", backendSource: "manual", source: .manual,
                     status: "backlog", project: "P", author: nil, number: nil, url: nil, isUnseen: true)
        ])

        try await fake.removeTask(id: 1)

        #expect(try await fake.task(id: 1) == nil)
    }

    @Test
    func fakeStoreCreateManualTaskAppendsAndReturnsItem() async throws {
        let fake = FakeTaskStore()

        let created = try await fake.createManualTask(title: "Buy milk", project: "Errands", tags: ["home"])

        #expect(created.title == "Buy milk")
        #expect(created.source == .manual)
        let all = try await fake.tasks(matching: .default)
        #expect(all.count == 1)
        #expect(all[0].id == created.id)
    }

    @Test
    func fakeStoreSearchReturnsTokenAndMatches() async throws {
        let fake = FakeTaskStore()
        await fake.setTasks([
            TaskItem(id: 1, title: "Review PR for the dashboard", backendSource: "pr_review",
                     source: .review, status: "review requested", project: "ui", author: "someone",
                     number: nil, url: nil, isUnseen: true),
            TaskItem(id: 2, title: "Buy milk", backendSource: "manual", source: .manual,
                     status: "backlog", project: "Errands", author: nil, number: nil, url: nil, isUnseen: true)
        ])

        let results = try await fake.searchTasks(query: "review dashboard", source: nil, status: nil, project: nil, limit: 10)

        #expect(results.count == 1)
        #expect(results[0].id == 1)
    }
}
