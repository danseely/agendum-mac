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
    ///
    /// Creates the parent directory (mode 0o700) and chmod-s the resulting db file
    /// to 0o600, matching Python `init_db` (`db.py:43-51`). On a fresh install this
    /// init may run before Python ever has, so Swift owns directory creation too.
    public init(path: URL) throws {
        let parent = path.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: parent,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        var config = Configuration()
        config.busyMode = .timeout(5.0)
        let pool = try DatabasePool(path: path.path, configuration: config)
        try DatabaseSchema.prepare(pool)
        // chmod 0o600 once the file exists. WAL/SHM siblings are created on first
        // write; chmod them too if present. SQLite emits them with default umask,
        // so this is best-effort and safe to skip if they don't exist yet.
        let fm = FileManager.default
        if fm.fileExists(atPath: path.path) {
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
        }
        for sibling in ["-wal", "-shm"] {
            let sib = path.path + sibling
            if fm.fileExists(atPath: sib) {
                try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: sib)
            }
        }
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
    /// `gh_author_name`, and `tags`. Matches `task_api.search_tasks` (and
    /// `task_api._task_haystack`) behavior: case-folded, whitespace-tokenized, all
    /// tokens must match, returns at most `limit`. Search runs at the `TaskRecord`
    /// level (not `TaskItem`) so it can reach fields the domain mapping discards
    /// (`gh_repo`, `tags`, etc.).
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
        // Match Python `search_tasks`: candidate set is `get_active_tasks` (no
        // LIMIT) filtered by source/status/project/includeSeen, then the
        // haystack-AND match short-circuits at `cap`. Build the SQL by reusing
        // filterSQL's WHERE+ORDER BY but skipping its LIMIT clause.
        let (whereSQL, args) = searchCandidateSQL(
            source: source, status: status, project: project
        )
        let records = try await database.read { db in
            try TaskRecord.fetchAll(db, sql: whereSQL, arguments: args)
        }
        var matches: [TaskItem] = []
        matches.reserveCapacity(cap)
        for record in records {
            let haystack = taskHaystack(record)
            if tokens.allSatisfy({ haystack.contains($0) }) {
                guard let item = record.toTaskItem() else { continue }
                matches.append(item)
                if matches.count >= cap { break }
            }
        }
        return matches
    }

    /// Build the candidate-set SQL for `searchTasks`: same WHERE clauses as
    /// `filterSQL` (terminal-status exclusion + source/status/project filters,
    /// `includeSeen=true`) and the same ORDER BY, but no LIMIT — Python's
    /// `search_tasks` iterates `get_active_tasks` unbounded and short-circuits
    /// in the haystack loop.
    private nonisolated func searchCandidateSQL(
        source: String?,
        status: String?,
        project: String?
    ) -> (String, StatementArguments) {
        var conditions: [String] = []
        var args: [DatabaseValueConvertible?] = []
        if status == nil {
            let placeholders = terminalStatuses.map { _ in "?" }.joined(separator: ", ")
            conditions.append("status NOT IN (\(placeholders))")
            args.append(contentsOf: terminalStatuses.map { $0 as DatabaseValueConvertible? })
        }
        if let source {
            conditions.append("source = ?")
            args.append(source)
        }
        if let status {
            conditions.append("status = ?")
            args.append(status)
        }
        if let project {
            conditions.append("project = ?")
            args.append(project)
        }
        var sql = "SELECT * FROM \(DatabaseSchema.tasksTable)"
        if !conditions.isEmpty {
            sql += " WHERE " + conditions.joined(separator: " AND ")
        }
        sql += " ORDER BY seen ASC, updated_at DESC, id DESC"
        return (sql, StatementArguments(args))
    }

    /// Mirrors Python `task_api._task_haystack`: case-folded, whitespace-joined.
    /// Includes the raw record fields (so `gh_repo`, `tags`, `gh_url`, etc. are
    /// searchable). Tags are JSON-decoded when possible; otherwise included raw.
    private nonisolated func taskHaystack(_ record: TaskRecord) -> String {
        var parts: [String] = [record.title]
        if let project = record.project { parts.append(project) }
        if let ghRepo = record.ghRepo { parts.append(ghRepo) }
        if let ghURL = record.ghURL { parts.append(ghURL) }
        if let ghAuthor = record.ghAuthor { parts.append(ghAuthor) }
        if let ghAuthorName = record.ghAuthorName { parts.append(ghAuthorName) }
        if let tags = record.tags, !tags.isEmpty {
            // Match Python `task_api._normalize_tags`: JSON-decode then treat:
            //   - array → flatten members as strings
            //   - non-array JSON value → singleton list of stringified value
            //   - non-JSON string → singleton [tags]
            if let data = tags.data(using: .utf8),
               let value = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
                if let arr = value as? [Any] {
                    parts.append(contentsOf: arr.map { String(describing: $0) })
                } else {
                    parts.append(String(describing: value))
                }
            } else {
                parts.append(tags)
            }
        }
        return parts.joined(separator: " ").lowercased()
    }

    // MARK: - Sync writes (consumed by AgendumSync.ApplyDiff)

    /// Looks up a task's primary key by its `gh_url`. Returns `nil` if no row matches.
    /// Mirrors Python `db.find_task_by_gh_url` (returns id only — sync only needs the id).
    public func findTaskID(forGHURL ghURL: String) async throws -> Int? {
        try await database.read { db in
            let row = try Row.fetchOne(
                db,
                sql: "SELECT id FROM \(DatabaseSchema.tasksTable) WHERE gh_url = ? LIMIT 1",
                arguments: [ghURL]
            )
            guard let row, let id = row["id"] as Int64? else { return nil }
            return Int(id)
        }
    }

    /// Inserts a brand-new sync-discovered task. Sets `seen=0` (newly synced rows are
    /// unseen so the dashboard surfaces them) and stamps `last_changed_at`,
    /// `created_at`, and `updated_at` to `now`. Mirrors Python `db.add_task`.
    @discardableResult
    public func insertSyncedTask(
        title: String,
        source: String,
        status: String,
        ghURL: String?,
        ghRepo: String?,
        ghNumber: Int?,
        ghAuthor: String?,
        ghAuthorName: String?,
        project: String?,
        tags: String?,
        now: String
    ) async throws -> Int {
        let id = try await database.write { db -> Int64 in
            try db.execute(sql: """
                INSERT INTO tasks
                  (title, source, status, project, gh_repo, gh_url, gh_number,
                   gh_author, gh_author_name, tags, seen,
                   last_changed_at, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?, ?)
                """, arguments: [
                    title, source, status, project, ghRepo, ghURL, ghNumber,
                    ghAuthor, ghAuthorName, tags,
                    now, now, now
                ])
            return db.lastInsertedRowID
        }
        return Int(id)
    }

    /// Sparse update for sync — writes exactly the columns named by `changedColumns`.
    /// Named columns can be set to NULL by passing nil. Always bumps `updated_at`
    /// (matches Python `db.update_task`). When
    /// `resetSeen == true`, also writes `seen = 0` and `last_changed_at = now`
    /// (matches the syncer's create-race + to_update paths in `syncer.py:337-395`).
    /// Silent no-op if `id` is not found.
    public func applySyncUpdate(
        id: Int,
        title: String? = nil,
        source: String? = nil,
        status: String? = nil,
        project: String? = nil,
        ghRepo: String? = nil,
        ghNumber: Int? = nil,
        ghAuthor: String? = nil,
        ghAuthorName: String? = nil,
        tags: String? = nil,
        changedColumns: Set<String>,
        resetSeen: Bool,
        now: String
    ) async throws {
        var assignments: [String] = []
        var args: [DatabaseValueConvertible?] = []
        func add(_ column: String, _ value: DatabaseValueConvertible?) {
            assignments.append("\(column) = ?")
            args.append(value)
        }
        if changedColumns.contains("title") { add("title", title) }
        if changedColumns.contains("source") { add("source", source) }
        if changedColumns.contains("status") { add("status", status) }
        if changedColumns.contains("project") { add("project", project) }
        if changedColumns.contains("gh_repo") { add("gh_repo", ghRepo) }
        if changedColumns.contains("gh_number") { add("gh_number", ghNumber) }
        if changedColumns.contains("gh_author") { add("gh_author", ghAuthor) }
        if changedColumns.contains("gh_author_name") { add("gh_author_name", ghAuthorName) }
        if changedColumns.contains("tags") { add("tags", tags) }
        if resetSeen {
            add("seen", 0)
            add("last_changed_at", now)
        }
        // Always touch updated_at (Python `update_task` appends it on every call).
        add("updated_at", now)
        args.append(id)
        let sql = "UPDATE \(DatabaseSchema.tasksTable) SET \(assignments.joined(separator: ", ")) WHERE id = ?"
        let stmtArgs = StatementArguments(args)
        try await database.write { db in
            try db.execute(sql: sql, arguments: stmtArgs)
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
