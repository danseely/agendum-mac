import Foundation

public struct Workspace: Codable, Equatable, Sendable {
    public let id: String
    public let namespace: String?
    public let displayName: String
    public let configPath: String
    public let dbPath: String
    public let isCurrent: Bool

    public init(
        id: String,
        namespace: String?,
        displayName: String,
        configPath: String,
        dbPath: String,
        isCurrent: Bool
    ) {
        self.id = id
        self.namespace = namespace
        self.displayName = displayName
        self.configPath = configPath
        self.dbPath = dbPath
        self.isCurrent = isCurrent
    }
}

public struct AuthStatus: Codable, Equatable, Sendable {
    public let ghFound: Bool
    public let ghPath: String?
    public let authenticated: Bool
    public let username: String?
    public let workspaceGhConfigDir: String
    public let repairInstructions: String?
    public let repairCommand: String?

    public init(
        ghFound: Bool,
        ghPath: String?,
        authenticated: Bool,
        username: String?,
        workspaceGhConfigDir: String,
        repairInstructions: String?,
        repairCommand: String?
    ) {
        self.ghFound = ghFound
        self.ghPath = ghPath
        self.authenticated = authenticated
        self.username = username
        self.workspaceGhConfigDir = workspaceGhConfigDir
        self.repairInstructions = repairInstructions
        self.repairCommand = repairCommand
    }
}

public struct AuthDiagnostics: Codable, Equatable, Sendable {
    public let gh: GHInstallation
    public let auth: AuthStatus
    public let host: String
    public let pathEntries: [String]

    public init(
        gh: GHInstallation,
        auth: AuthStatus,
        host: String,
        pathEntries: [String]
    ) {
        self.gh = gh
        self.auth = auth
        self.host = host
        self.pathEntries = pathEntries
    }

    public struct GHInstallation: Codable, Equatable, Sendable {
        public let found: Bool
        public let path: String?
        public let version: String?
        public let installed: Bool

        public init(found: Bool, path: String?, version: String?, installed: Bool) {
            self.found = found
            self.path = path
            self.version = version
            self.installed = installed
        }
    }
}

public struct SyncStatus: Codable, Equatable, Sendable {
    public let state: String
    public let lastSyncAt: String?
    public let lastError: String?
    public let changes: Int
    public let hasAttentionItems: Bool

    public init(
        state: String,
        lastSyncAt: String?,
        lastError: String?,
        changes: Int,
        hasAttentionItems: Bool
    ) {
        self.state = state
        self.lastSyncAt = lastSyncAt
        self.lastError = lastError
        self.changes = changes
        self.hasAttentionItems = hasAttentionItems
    }
}

public struct WorkspaceSelection: Codable, Equatable, Sendable {
    public let workspace: Workspace
    public let auth: AuthStatus
    public let sync: SyncStatus

    public init(workspace: Workspace, auth: AuthStatus, sync: SyncStatus) {
        self.workspace = workspace
        self.auth = auth
        self.sync = sync
    }
}

public struct TaskItem: Identifiable, Hashable, Sendable {
    public let id: Int
    public let title: String
    public let backendSource: String
    public let source: TaskSource
    public let status: String
    public let project: String
    public let author: String?
    public let number: Int?
    public let url: URL?
    public let isUnseen: Bool

    public init(
        id: Int,
        title: String,
        backendSource: String,
        source: TaskSource,
        status: String,
        project: String,
        author: String?,
        number: Int?,
        url: URL?,
        isUnseen: Bool
    ) {
        self.id = id
        self.title = title
        self.backendSource = backendSource
        self.source = source
        self.status = status
        self.project = project
        self.author = author
        self.number = number
        self.url = url
        self.isUnseen = isUnseen
    }
}

public enum TaskSource: String, CaseIterable, Identifiable, Sendable {
    case all = "All"
    case authored = "My Pull Requests"
    case review = "Reviews Requested"
    case issues = "Issues"
    case manual = "Manual"

    public var id: String { rawValue }

    public static let `default`: TaskSource = .all

    public static let displayOrder: [TaskSource] = [
        .authored,
        .review,
        .issues,
        .manual,
    ]

    public init(backendSource: String) {
        switch backendSource {
        case "pr_authored":
            self = .authored
        case "pr_review":
            self = .review
        case "issue":
            self = .issues
        case "manual":
            self = .manual
        default:
            self = .manual
        }
    }
}

public struct TaskDisplaySection: Identifiable, Equatable, Sendable {
    public let source: TaskSource
    public let tasks: [TaskItem]

    public var id: TaskSource.ID { source.id }
    public var title: String { source.rawValue }

    public init(source: TaskSource, tasks: [TaskItem]) {
        self.source = source
        self.tasks = tasks
    }

    public static func sections(
        for tasks: [TaskItem],
        selection: TaskSource = .default
    ) -> [TaskDisplaySection] {
        let sources = selection == .all ? TaskSource.displayOrder : [selection]

        return sources.compactMap { source in
            guard source != .all else { return nil }
            let sourceTasks = tasks.filter { $0.source == source }
            guard !sourceTasks.isEmpty else { return nil }
            return TaskDisplaySection(source: source, tasks: sourceTasks)
        }
    }

    public static func task(
        withID id: TaskItem.ID,
        in sections: [TaskDisplaySection]
    ) -> TaskItem? {
        sections
            .lazy
            .flatMap(\.tasks)
            .first { $0.id == id }
    }

    public static func containsTask(
        withID id: TaskItem.ID,
        in sections: [TaskDisplaySection]
    ) -> Bool {
        task(withID: id, in: sections) != nil
    }
}

public struct TaskListFilters: Equatable, Sendable {
    public var source: String?
    public var status: String?
    public var project: String?
    public var includeSeen: Bool
    public var limit: Int

    public init(
        source: String? = nil,
        status: String? = nil,
        project: String? = nil,
        includeSeen: Bool = true,
        limit: Int = 50
    ) {
        self.source = source
        self.status = status
        self.project = project
        self.includeSeen = includeSeen
        self.limit = limit
    }

    public static let `default` = TaskListFilters()

    public static let allowedLimits: [Int] = [25, 50, 100, 200]
}
