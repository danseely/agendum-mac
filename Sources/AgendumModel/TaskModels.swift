import Foundation

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
