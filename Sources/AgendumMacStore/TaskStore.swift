import Foundation
import GRDB
import AgendumFeature

/// Statuses Python's `get_active_tasks` excludes from the default list.
/// Mirrors `Backend/agendum_engine/agendum/db.py` `TERMINAL_STATUSES`.
private let terminalStatuses: [String] = ["merged", "closed", "done"]

public enum TaskStoreError: Error, Equatable, Sendable {
    case invalidInput(String)
    case notFound(Int)
}

public actor TaskStore: TaskStoreProviding {
    /// Storage handle. `DatabasePool` for file-based DBs (opens in WAL mode by default,
    /// matching Python's `PRAGMA journal_mode=WAL` so the helper and Swift can coexist
    /// at the same SQLite file during the speed-run port). `DatabaseQueue` for in-memory
    /// test DBs (DatabasePool does not support in-memory).
    private let database: any DatabaseWriter
    /// Matches Python `datetime.now(timezone.utc).isoformat()` exactly so Swift-written
    /// `updated_at` / `last_seen_at` strings sort lexicographically against Python's
    /// (which produce `YYYY-MM-DDTHH:MM:SS.ffffff+00:00`). `ISO8601DateFormatter` would
    /// emit a `Z` suffix and only second precision, breaking mixed sort order.
    private let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS'+00:00'"
        return f
    }()

    /// Opens or creates the task database at `path`, running all schema migrations.
    /// Uses `DatabasePool` (WAL mode) so Python helper writes and Swift writes can
    /// coexist on the same SQLite file during the speed-run port.
    public init(path: URL) throws {
        var config = Configuration()
        config.busyMode = .timeout(5.0)
        let pool = try DatabasePool(path: path.path, configuration: config)
        try DatabaseSchema.prepare(pool)
        database = pool
    }

    /// In-memory database for tests. `DatabaseQueue` since `DatabasePool` does not
    /// support in-memory backing.
    init(inMemory: Void = ()) throws {
        let queue = try DatabaseQueue()
        try DatabaseSchema.prepare(queue)
        database = queue
    }

    public func tasks(matching filters: TaskListFilters) async throws -> [TaskItem] {
        let (sql, args) = filterSQL(matching: filters)
        return try await database.read { db in
            try TaskRecord.fetchAll(db, sql: sql, arguments: args)
                .compactMap { $0.toTaskItem() }
        }
    }

    public nonisolated func observe(matching filters: TaskListFilters) -> AsyncStream<[TaskItem]> {
        let (sql, args) = filterSQL(matching: filters)
        let db = database
        let (stream, continuation) = AsyncStream.makeStream(of: [TaskItem].self)
        let task = Task {
            let observation = ValueObservation.tracking { database in
                try TaskRecord.fetchAll(database, sql: sql, arguments: args)
                    .compactMap { $0.toTaskItem() }
            }
            do {
                for try await items in observation.values(in: db) {
                    continuation.yield(items)
                }
            } catch {
                logger.error("TaskStore observation error: \(error)")
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    public func task(id: TaskItem.ID) async throws -> TaskItem? {
        let taskID = id
        return try await database.read { db in
            try TaskRecord.fetchOne(db, key: taskID)?.toTaskItem()
        }
    }

    public func markSeen(id: TaskItem.ID) async throws {
        let taskID = id
        let now = timestampFormatter.string(from: Date())
        try await database.write { db in
            try db.execute(
                sql: "UPDATE tasks SET seen = 1, last_seen_at = ?, updated_at = ? WHERE id = ?",
                arguments: [now, now, taskID]
            )
        }
    }

    /// Updates a task's status and bumps `updated_at` (matches Python `update_task`).
    /// Used for markReviewed / markInProgress / moveToBacklog / markDone paths.
    /// Silent no-op if `id` is not found.
    public func updateTaskStatus(id: TaskItem.ID, status: String) async throws {
        let taskID = id
        let now = timestampFormatter.string(from: Date())
        try await database.write { db in
            try db.execute(
                sql: "UPDATE tasks SET status = ?, updated_at = ? WHERE id = ?",
                arguments: [status, now, taskID]
            )
        }
    }

    /// Removes a task. Silent no-op if `id` is not found. Mirrors `db.remove_task`.
    public func removeTask(id: TaskItem.ID) async throws {
        let taskID = id
        try await database.write { db in
            try db.execute(
                sql: "DELETE FROM tasks WHERE id = ?",
                arguments: [taskID]
            )
        }
    }

    /// Creates a manual task (`source = "manual"`, `status = "backlog"`). Mirrors
    /// `task_api.create_manual_task` + `db.add_task`. `tags` is encoded as a JSON
    /// array string to match Python's storage format.
    @discardableResult
    public func createManualTask(
        title: String,
        project: String? = nil,
        tags: [String]? = nil
    ) async throws -> TaskItem {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw TaskStoreError.invalidInput("title must not be empty")
        }
        let now = timestampFormatter.string(from: Date())
        let tagsJSON: String?
        if let tags, !tags.isEmpty {
            let data = try JSONSerialization.data(withJSONObject: tags)
            tagsJSON = String(data: data, encoding: .utf8)
        } else {
            tagsJSON = nil
        }
        let insertedID = try await database.write { db -> Int64 in
            try db.execute(sql: """
                INSERT INTO tasks
                  (title, source, status, project, tags, last_changed_at, created_at, updated_at)
                VALUES (?, 'manual', 'backlog', ?, ?, ?, ?, ?)
                """, arguments: [trimmed, project, tagsJSON, now, now, now])
            return db.lastInsertedRowID
        }
        guard let item = try await task(id: Int(insertedID)) else {
            throw TaskStoreError.notFound(Int(insertedID))
        }
        return item
    }

    /// Token-AND search across `title`, `project`, `gh_repo`, `gh_url`, `gh_author`,
    /// `gh_author_name`, and `tags`. Matches `task_api.search_tasks` behavior:
    /// case-folded, whitespace-tokenized, all tokens must match, returns at most `limit`.
    public func searchTasks(
        query: String,
        source: String? = nil,
        status: String? = nil,
        project: String? = nil,
        limit: Int = 20
    ) async throws -> [TaskItem] {
        let tokens = query
            .split(whereSeparator: { $0.isWhitespace })
            .map { String($0).lowercased() }
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else {
            throw TaskStoreError.invalidInput("query must not be empty")
        }
        let cap = max(1, min(limit, 200))
        // Reuse filterSQL for the candidate set (with includeSeen=true to match Python),
        // then token-filter in Swift to mirror task_api._task_haystack semantics.
        let baseFilters = TaskListFilters(
            source: source, status: status, project: project,
            includeSeen: true, limit: 200
        )
        let candidates = try await tasks(matching: baseFilters)
        var matches: [TaskItem] = []
        matches.reserveCapacity(cap)
        for item in candidates {
            let haystack = taskHaystack(item).lowercased()
            if tokens.allSatisfy({ haystack.contains($0) }) {
                matches.append(item)
                if matches.count >= cap { break }
            }
        }
        return matches
    }

    private nonisolated func taskHaystack(_ item: TaskItem) -> String {
        var parts: [String] = [item.title, item.project, item.backendSource]
        if let author = item.author { parts.append(author) }
        if let url = item.url { parts.append(url.absoluteString) }
        return parts.joined(separator: " ")
    }

    // MARK: - Internal test helpers

    func insert(_ record: TaskRecord) async throws {
        try await database.write { db in try record.insert(db) }
    }

    func rawRecord(id: Int64) async throws -> TaskRecord? {
        try await database.read { db in try TaskRecord.fetchOne(db, key: id) }
    }

    func insertRaw(
        id: Int64,
        title: String,
        source: String,
        status: String,
        seen: Int?,
        lastChangedAt: String?,
        createdAt: String?,
        updatedAt: String?
    ) async throws {
        let id = id
        try await database.write { db in
            try db.execute(sql: """
                INSERT INTO tasks (id, title, source, status, seen, last_changed_at, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [id, title, source, status, seen, lastChangedAt, createdAt, updatedAt])
        }
    }

    // MARK: - Private

    private nonisolated func filterSQL(matching filters: TaskListFilters) -> (String, StatementArguments) {
        var conditions: [String] = []
        var args: [DatabaseValueConvertible?] = []

        // Match Python `get_active_tasks`: hard-exclude terminal statuses so the
        // dashboard never surfaces merged/closed/done rows. An explicit `status`
        // filter takes precedence and bypasses this default (e.g., a future
        // archive view could pass `status: "merged"` to look at terminal rows).
        if filters.status == nil {
            let placeholders = terminalStatuses.map { _ in "?" }.joined(separator: ", ")
            conditions.append("status NOT IN (\(placeholders))")
            args.append(contentsOf: terminalStatuses.map { $0 as DatabaseValueConvertible? })
        }

        if let source = filters.source {
            conditions.append("source = ?")
            args.append(source)
        }
        if let status = filters.status {
            conditions.append("status = ?")
            args.append(status)
        }
        if let project = filters.project {
            conditions.append("project = ?")
            args.append(project)
        }
        if !filters.includeSeen {
            conditions.append("(seen = 0 OR seen IS NULL)")
        }

        var sql = "SELECT * FROM \(DatabaseSchema.tasksTable)"
        if !conditions.isEmpty {
            sql += " WHERE " + conditions.joined(separator: " AND ")
        }
        // Match Python db.py ordering: unseen first, then most-recently-updated.
        // (Source grouping is omitted; TaskDisplaySection handles that at the display layer.)
        sql += " ORDER BY seen ASC, updated_at DESC, id DESC"
        sql += " LIMIT ?"
        args.append(max(1, min(filters.limit, 200)))

        return (sql, StatementArguments(args))
    }
}

extension TaskRecord {
    func toTaskItem() -> TaskItem? {
        guard let id else { return nil }
        return TaskItem(
            id: Int(id),
            title: title,
            backendSource: source,
            source: TaskSource(backendSource: source),
            status: status,
            project: project ?? ghRepo ?? "No project",
            author: ghAuthorName ?? ghAuthor,
            number: ghNumber.map(Int.init),
            url: ghURL.flatMap(URL.init(string:)),
            isUnseen: (seen ?? 0) == 0
        )
    }
}
