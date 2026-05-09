@testable import AgendumMacStore
import GRDB
import Testing

struct TaskRecordTests {
    @Test
    func migratorCreatesCurrentPythonTaskSchema() throws {
        let dbQueue = try makeMigratedDatabase()

        let columns = try tableColumns(in: dbQueue)

        #expect(columns.map(\.name) == [
            "id",
            "title",
            "source",
            "status",
            "project",
            "gh_repo",
            "gh_url",
            "gh_node_id",
            "gh_number",
            "gh_author",
            "gh_author_name",
            "tags",
            "seen",
            "last_changed_at",
            "last_seen_at",
            "created_at",
            "updated_at",
        ])
        #expect(columns.first(named: "id")?.type == "INTEGER")
        #expect(columns.first(named: "id")?.primaryKey == 1)
        #expect(columns.first(named: "title")?.notNull == true)
        #expect(columns.first(named: "source")?.notNull == true)
        #expect(columns.first(named: "status")?.notNull == true)
        #expect(columns.first(named: "seen")?.defaultValue == "1")
        #expect(columns.first(named: "created_at")?.defaultValue == "datetime('now')")
        #expect(columns.first(named: "updated_at")?.defaultValue == "datetime('now')")
    }

    @Test
    func migratorCreatesCurrentPythonIndexesAndUniqueURLConstraint() throws {
        let dbQueue = try makeMigratedDatabase()

        let indexes = try dbQueue.read { db in
            try Row.fetchAll(db, sql: "PRAGMA index_list(tasks)")
                .map(IndexInfo.init(row:))
        }

        #expect(indexes.contains(IndexInfo(name: "idx_tasks_source", unique: false, partial: false)))
        #expect(indexes.contains(IndexInfo(name: "idx_tasks_status", unique: false, partial: false)))
        #expect(indexes.contains(IndexInfo(name: "idx_tasks_gh_url", unique: false, partial: true)))
        #expect(indexes.contains(IndexInfo(name: "idx_tasks_gh_node_id", unique: false, partial: true)))

        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO tasks (title, source, status, gh_url)
                VALUES ('First', 'manual', 'backlog', 'https://github.com/example/repo/issues/1');
                """)
        }

        var duplicateURLFailed = false
        do {
            try dbQueue.write { db in
                try db.execute(sql: """
                    INSERT INTO tasks (title, source, status, gh_url)
                    VALUES ('Second', 'manual', 'backlog', 'https://github.com/example/repo/issues/1');
                    """)
            }
        } catch {
            duplicateURLFailed = true
        }

        #expect(duplicateURLFailed)
    }

    @Test
    func taskRecordRoundTripsThroughInMemoryDatabase() throws {
        let dbQueue = try makeMigratedDatabase()
        let record = TaskRecord(
            title: "Review GRDB migration",
            source: "pr_review",
            status: "review requested",
            project: nil,
            ghRepo: "danseely/agendum-mac",
            ghURL: "https://github.com/danseely/agendum-mac/pull/44",
            ghNodeID: "PR_kwDOExample",
            ghNumber: 44,
            ghAuthor: "danseely",
            ghAuthorName: "Dan",
            tags: #"["swift","store"]"#,
            seen: 0,
            lastChangedAt: "2026-05-08T18:00:00+00:00",
            lastSeenAt: nil,
            createdAt: "2026-05-08T18:00:00+00:00",
            updatedAt: "2026-05-08T18:01:00+00:00"
        )

        try dbQueue.write { db in
            try record.insert(db)
        }

        let stored = try #require(try dbQueue.read { db in
            try TaskRecord.fetchOne(db, key: 1)
        })

        #expect(stored.id == 1)
        #expect(stored.title == record.title)
        #expect(stored.source == record.source)
        #expect(stored.status == record.status)
        #expect(stored.project == record.project)
        #expect(stored.ghRepo == record.ghRepo)
        #expect(stored.ghURL == record.ghURL)
        #expect(stored.ghNodeID == record.ghNodeID)
        #expect(stored.ghNumber == record.ghNumber)
        #expect(stored.ghAuthor == record.ghAuthor)
        #expect(stored.ghAuthorName == record.ghAuthorName)
        #expect(stored.tags == record.tags)
        #expect(stored.seen == record.seen)
        #expect(stored.lastChangedAt == record.lastChangedAt)
        #expect(stored.lastSeenAt == record.lastSeenAt)
        #expect(stored.createdAt == record.createdAt)
        #expect(stored.updatedAt == record.updatedAt)
    }

    @Test
    func taskRecordReadsNullableSeenFromCurrentSchema() throws {
        let dbQueue = try makePreparedDatabase()

        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO tasks (title, source, status, seen, last_changed_at, created_at, updated_at)
                VALUES (
                    'Imported nullable seen task',
                    'manual',
                    'backlog',
                    NULL,
                    '2026-05-08T18:00:00+00:00',
                    '2026-05-08T18:00:00+00:00',
                    '2026-05-08T18:00:00+00:00'
                );
                """)
        }

        let stored = try #require(try dbQueue.read { db in
            try TaskRecord.fetchOne(db, key: 1)
        })

        #expect(stored.seen == nil)
    }

    @Test
    func taskRecordInitializerRequiresExplicitTimestampDecision() {
        let record = TaskRecord(
            title: "Manual follow-up",
            source: "manual",
            status: "backlog",
            lastChangedAt: "2026-05-08T18:00:00+00:00",
            createdAt: "2026-05-08T18:00:00+00:00",
            updatedAt: "2026-05-08T18:00:00+00:00"
        )

        #expect(record.lastChangedAt != nil)
        #expect(record.createdAt != nil)
        #expect(record.updatedAt != nil)
    }

    @Test
    func persistingLegacyRecordWithNilTimestampsThrows() throws {
        let dbQueue = try makeMigratedDatabase()

        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO tasks (title, source, status, last_changed_at, created_at, updated_at)
                VALUES ('Imported task', 'manual', 'backlog', NULL, NULL, NULL);
                """)
        }

        var legacyRecord = try #require(try dbQueue.read { db in
            try TaskRecord.fetchOne(db, key: 1)
        })
        legacyRecord.id = nil

        var insertFailed = false
        do {
            try dbQueue.write { db in
                try legacyRecord.insert(db)
            }
        } catch {
            insertFailed = true
        }

        #expect(insertFailed)
    }

    @Test
    func migratorOpensExistingCurrentSchemaDatabase() throws {
        let dbQueue = try DatabaseQueue()

        try dbQueue.write { db in
            try db.execute(sql: """
                CREATE TABLE tasks (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    title TEXT NOT NULL,
                    source TEXT NOT NULL,
                    status TEXT NOT NULL,
                    project TEXT,
                    gh_repo TEXT,
                    gh_url TEXT UNIQUE,
                    gh_node_id TEXT,
                    gh_number INTEGER,
                    gh_author TEXT,
                    gh_author_name TEXT,
                    tags TEXT,
                    seen INTEGER DEFAULT 1,
                    last_changed_at TEXT,
                    last_seen_at TEXT,
                    created_at TEXT DEFAULT (datetime('now')),
                    updated_at TEXT DEFAULT (datetime('now'))
                );
                INSERT INTO tasks (title, source, status)
                VALUES ('Legacy active task', 'manual', 'active');
                """)
        }

        try DatabaseSchema.migrator().migrate(dbQueue)

        let status = try dbQueue.read { db in
            try String.fetchOne(db, sql: "SELECT status FROM tasks WHERE id = 1")
        }

        #expect(status == "backlog")
    }

    @Test
    func prepareRepeatsLegacyActiveStatusCleanupAfterMigration() throws {
        let dbQueue = try makePreparedDatabase()

        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO tasks (title, source, status)
                VALUES ('Late active task', 'manual', 'active');
                """)
        }

        try DatabaseSchema.prepare(dbQueue)

        let status = try dbQueue.read { db in
            try String.fetchOne(db, sql: "SELECT status FROM tasks WHERE id = 1")
        }

        #expect(status == "backlog")
    }

    @Test
    func migratorAddsMissingGitHubNodeIDColumnToLegacyDatabase() throws {
        let dbQueue = try DatabaseQueue()

        try dbQueue.write { db in
            try db.execute(sql: """
                CREATE TABLE tasks (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    title TEXT NOT NULL,
                    source TEXT NOT NULL,
                    status TEXT NOT NULL,
                    project TEXT,
                    gh_repo TEXT,
                    gh_url TEXT UNIQUE,
                    gh_number INTEGER,
                    gh_author TEXT,
                    gh_author_name TEXT,
                    tags TEXT,
                    seen INTEGER DEFAULT 1,
                    last_changed_at TEXT,
                    last_seen_at TEXT,
                    created_at TEXT DEFAULT (datetime('now')),
                    updated_at TEXT DEFAULT (datetime('now'))
                );
                INSERT INTO tasks (title, source, status)
                VALUES ('Legacy active task', 'manual', 'active');
                """)
        }

        try DatabaseSchema.migrator().migrate(dbQueue)

        let columns = try tableColumns(in: dbQueue)
        let status = try dbQueue.read { db in
            try String.fetchOne(db, sql: "SELECT status FROM tasks WHERE id = 1")
        }

        #expect(columns.map(\.name).contains("gh_node_id"))
        #expect(columns.first(named: "gh_node_id")?.type == "TEXT")
        #expect(status == "backlog")
    }
}

private func makePreparedDatabase() throws -> DatabaseQueue {
    let dbQueue = try DatabaseQueue()
    try DatabaseSchema.prepare(dbQueue)
    return dbQueue
}

private func makeMigratedDatabase() throws -> DatabaseQueue {
    let dbQueue = try DatabaseQueue()
    try DatabaseSchema.migrator().migrate(dbQueue)
    return dbQueue
}

private func tableColumns(in dbQueue: DatabaseQueue) throws -> [ColumnInfo] {
    try dbQueue.read { db in
        try Row.fetchAll(db, sql: "PRAGMA table_info(tasks)")
            .map(ColumnInfo.init(row:))
    }
}

private struct ColumnInfo {
    var name: String
    var type: String
    var notNull: Bool
    var defaultValue: String?
    var primaryKey: Int

    init(row: Row) {
        name = row["name"]
        type = row["type"]
        let notNullValue: Int = row["notnull"]
        notNull = notNullValue == 1
        defaultValue = row["dflt_value"]
        primaryKey = row["pk"]
    }
}

private struct IndexInfo: Equatable {
    var name: String
    var unique: Bool
    var partial: Bool

    init(name: String, unique: Bool, partial: Bool) {
        self.name = name
        self.unique = unique
        self.partial = partial
    }

    init(row: Row) {
        name = row["name"]
        let uniqueValue: Int = row["unique"]
        let partialValue: Int = row["partial"]
        unique = uniqueValue == 1
        partial = partialValue == 1
    }
}

private extension Array where Element == ColumnInfo {
    func first(named name: String) -> ColumnInfo? {
        first { $0.name == name }
    }
}
