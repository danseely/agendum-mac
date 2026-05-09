import Foundation
import GRDB

/// The current Python-backed task schema, preserved byte-for-byte at the
/// database boundary so Swift can take ownership without data migration churn.
public enum DatabaseSchema {
    public static let tasksTable = "tasks"

    public static func migrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_current_python_tasks_schema") { db in
            logger.notice("Applying current Python tasks schema migration")
            try db.execute(sql: currentPythonSchemaSQL)
            try ensureTaskColumn(db, name: "gh_node_id", definition: "TEXT")
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_tasks_source ON tasks(source);
                CREATE INDEX IF NOT EXISTS idx_tasks_status ON tasks(status);
                CREATE INDEX IF NOT EXISTS idx_tasks_gh_url ON tasks(gh_url)
                    WHERE gh_url IS NOT NULL;
                CREATE INDEX IF NOT EXISTS idx_tasks_gh_node_id ON tasks(gh_node_id)
                    WHERE gh_node_id IS NOT NULL;
                """)
            try normalizeLegacyStatuses(db)
        }

        return migrator
    }

    public static func prepare(_ writer: any DatabaseWriter) throws {
        try migrator().migrate(writer)
        try writer.write { db in
            try normalizeLegacyStatuses(db)
        }
    }

    private static let currentPythonSchemaSQL = """
        CREATE TABLE IF NOT EXISTS tasks (
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
        """

    private static func ensureTaskColumn(
        _ db: Database,
        name: String,
        definition: String
    ) throws {
        let existingColumnNames = try Set(
            Row.fetchAll(db, sql: "PRAGMA table_info(tasks)")
                .compactMap { $0["name"] as String? }
        )
        if !existingColumnNames.contains(name) {
            try db.execute(sql: "ALTER TABLE tasks ADD COLUMN \(name) \(definition)")
        }
    }

    private static func normalizeLegacyStatuses(_ db: Database) throws {
        try db.execute(sql: "UPDATE tasks SET status = 'backlog' WHERE status = 'active'")
    }
}

public struct TaskRecord: Codable, Equatable, FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = DatabaseSchema.tasksTable

    public var id: Int64?
    public var title: String
    public var source: String
    public var status: String
    public var project: String?
    public var ghRepo: String?
    public var ghURL: String?
    public var ghNodeID: String?
    public var ghNumber: Int64?
    public var ghAuthor: String?
    public var ghAuthorName: String?
    public var tags: String?
    public var seen: Int?
    public private(set) var lastChangedAt: String?
    public var lastSeenAt: String?
    public private(set) var createdAt: String?
    public private(set) var updatedAt: String?

    public init(
        id: Int64? = nil,
        title: String,
        source: String,
        status: String,
        project: String? = nil,
        ghRepo: String? = nil,
        ghURL: String? = nil,
        ghNodeID: String? = nil,
        ghNumber: Int64? = nil,
        ghAuthor: String? = nil,
        ghAuthorName: String? = nil,
        tags: String? = nil,
        seen: Int? = 1,
        lastChangedAt: String,
        lastSeenAt: String? = nil,
        createdAt: String,
        updatedAt: String
    ) {
        self.id = id
        self.title = title
        self.source = source
        self.status = status
        self.project = project
        self.ghRepo = ghRepo
        self.ghURL = ghURL
        self.ghNodeID = ghNodeID
        self.ghNumber = ghNumber
        self.ghAuthor = ghAuthor
        self.ghAuthorName = ghAuthorName
        self.tags = tags
        self.seen = seen
        self.lastChangedAt = lastChangedAt
        self.lastSeenAt = lastSeenAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public func encode(to container: inout PersistenceContainer) throws {
        guard
            let lastChangedAt,
            let createdAt,
            let updatedAt
        else {
            throw EncodingError.invalidValue(
                self,
                EncodingError.Context(
                    codingPath: [],
                    debugDescription: "TaskRecord persistence requires lastChangedAt, createdAt, and updatedAt"
                )
            )
        }

        container["id"] = id
        container["title"] = title
        container["source"] = source
        container["status"] = status
        container["project"] = project
        container["gh_repo"] = ghRepo
        container["gh_url"] = ghURL
        container["gh_node_id"] = ghNodeID
        container["gh_number"] = ghNumber
        container["gh_author"] = ghAuthor
        container["gh_author_name"] = ghAuthorName
        container["tags"] = tags
        container["seen"] = seen
        container["last_changed_at"] = lastChangedAt
        container["last_seen_at"] = lastSeenAt
        container["created_at"] = createdAt
        container["updated_at"] = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case source
        case status
        case project
        case ghRepo = "gh_repo"
        case ghURL = "gh_url"
        case ghNodeID = "gh_node_id"
        case ghNumber = "gh_number"
        case ghAuthor = "gh_author"
        case ghAuthorName = "gh_author_name"
        case tags
        case seen
        case lastChangedAt = "last_changed_at"
        case lastSeenAt = "last_seen_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
