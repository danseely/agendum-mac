public protocol TaskStoreProviding: Sendable {
    func tasks(matching filters: TaskListFilters) async throws -> [TaskItem]
    nonisolated func observe(matching filters: TaskListFilters) -> AsyncStream<[TaskItem]>
    func task(id: TaskItem.ID) async throws -> TaskItem?
    /// Marks the task with `id` as seen, updating `last_seen_at` and `updated_at`.
    /// - Note: If no task with `id` exists this is a silent no-op (0 rows affected).
    func markSeen(id: TaskItem.ID) async throws
}
