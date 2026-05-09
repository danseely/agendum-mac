import Foundation
import GRDB
import AgendumFeature

public actor TaskStore: TaskStoreProviding {
    private let database: DatabaseQueue
    private let timestampFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
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
        sql += " ORDER BY last_changed_at DESC, id DESC"
        sql += " LIMIT ?"
        args.append(filters.limit)

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
