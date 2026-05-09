public protocol TaskStoreProviding: Sendable {
    func tasks(matching filters: TaskListFilters) async throws -> [TaskItem]
    func observe(matching filters: TaskListFilters) -> AsyncStream<[TaskItem]>
    func task(id: TaskItem.ID) async throws -> TaskItem?
    func markSeen(id: TaskItem.ID) async throws
}
