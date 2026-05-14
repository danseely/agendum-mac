public protocol TaskStoreProviding: Sendable {
    func tasks(matching filters: TaskListFilters) async throws -> [TaskItem]
    nonisolated func observe(matching filters: TaskListFilters) -> AsyncStream<[TaskItem]>
    func task(id: TaskItem.ID) async throws -> TaskItem?
    /// Marks the task with `id` as seen, updating `last_seen_at` and `updated_at`.
    /// - Note: If no task with `id` exists this is a silent no-op (0 rows affected).
    func markSeen(id: TaskItem.ID) async throws
    /// Updates a task's `status` (e.g., "reviewed", "in progress", "backlog", "done")
    /// and bumps `updated_at`. Silent no-op on missing id.
    func updateTaskStatus(id: TaskItem.ID, status: String) async throws
    /// Removes a task from the store. Silent no-op on missing id.
    func removeTask(id: TaskItem.ID) async throws
    /// Creates a manual task (`source = "manual"`, `status = "backlog"`) and returns it.
    /// `tags` is encoded as a JSON array string in the underlying storage.
    @discardableResult
    func createManualTask(title: String, project: String?, tags: [String]?) async throws -> TaskItem
    /// Token-AND search across title/project/repo/url/author/author-name/tags.
    /// Case-folded, whitespace-tokenized, all tokens must match.
    func searchTasks(
        query: String,
        source: String?,
        status: String?,
        project: String?,
        limit: Int
    ) async throws -> [TaskItem]
}
