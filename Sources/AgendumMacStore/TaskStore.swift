import Foundation
import GRDB
import AgendumFeature

/// Statuses Python's `get_active_tasks` excludes from the default list.
/// Mirrors `Backend/agendum_engine/agendum/db.py` `TERMINAL_STATUSES`.
private let terminalStatuses: [String] = ["merged", "closed", "done"]

public actor TaskStore: TaskStoreProviding {
    private let database: DatabaseQueue
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
    public init(path: URL) throws {
        database = try DatabaseQueue(path: path.path)
        try DatabaseSchema.prepare(database)
    }

    /// In-memory database for tests.
    init(inMemory: Void = ()) throws {
        database = try DatabaseQueue()
        try DatabaseSchema.prepare(database)
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
