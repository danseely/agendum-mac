import AgendumMacCore
import Combine
import Foundation

public protocol AgendumBackendServicing: Sendable {
    func currentWorkspace() async throws -> Workspace
    func listWorkspaces() async throws -> [Workspace]
    func selectWorkspace(namespace: String?) async throws -> WorkspaceSelection
    func listTasks(source: String?, status: String?, project: String?, includeSeen: Bool, limit: Int) async throws -> [AgendumTask]
    func getTask(id: Int) async throws -> AgendumTask?
    func markTaskReviewed(id: Int) async throws -> AgendumTask
    func markTaskInProgress(id: Int) async throws -> AgendumTask
    func moveTaskToBacklog(id: Int) async throws -> AgendumTask
    func markTaskDone(id: Int) async throws -> AgendumTask
    func markTaskSeen(id: Int) async throws -> AgendumTask
    func removeTask(id: Int) async throws -> Bool
    func syncStatus() async throws -> SyncStatus
    func forceSync() async throws -> SyncStatus
    func authStatus() async throws -> AuthStatus
    func createManualTask(title: String, project: String?, tags: [String]?) async throws -> AgendumTask
}

extension AgendumBackendClient: AgendumBackendServicing {}

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

    init(task: AgendumTask) {
        id = task.id
        title = task.title
        backendSource = task.source
        source = TaskSource(backendSource: task.source)
        status = task.status
        project = task.project ?? "No project"
        author = task.ghAuthorName ?? task.ghAuthor
        number = task.ghNumber
        url = task.ghUrl.flatMap(URL.init(string:))
        isUnseen = !task.seen
    }

    public var availableDetailActions: Set<TaskDetailAction> {
        var actions: Set<TaskDetailAction> = [.remove]
        if url != nil {
            actions.insert(.openBrowser)
        }
        if isUnseen {
            actions.insert(.markSeen)
        }
        if source == .review {
            actions.insert(.markReviewed)
        }
        if backendSource == "manual" {
            actions.insert(status == "in progress" ? .moveToBacklog : .markInProgress)
            actions.insert(.markDone)
        }
        return actions
    }
}

public enum TaskSource: String, CaseIterable, Identifiable, Sendable {
    case authored = "My Pull Requests"
    case review = "Reviews Requested"
    case issues = "Issues & Manual"

    public var id: String { rawValue }

    init(backendSource: String) {
        switch backendSource {
        case "pr_authored":
            self = .authored
        case "pr_review":
            self = .review
        default:
            self = .issues
        }
    }
}

public enum TaskDetailAction: String, Hashable, Sendable {
    case openBrowser
    case markSeen
    case markReviewed
    case markInProgress
    case moveToBacklog
    case markDone
    case remove
}

public enum TaskDashboardCommand: Hashable, Sendable {
    case refresh
    case sync

    @MainActor
    public func perform(on model: BackendStatusModel) async {
        switch self {
        case .refresh:
            await model.refresh()
        case .sync:
            await model.forceSync()
        }
    }
}

public struct TaskDashboardCommands: Equatable, Sendable {
    public let toolbarRefresh: TaskDashboardCommand
    public let toolbarSync: TaskDashboardCommand
    public let menuSync: TaskDashboardCommand

    public static let standard = TaskDashboardCommands(
        toolbarRefresh: .refresh,
        toolbarSync: .sync,
        menuSync: .sync
    )
}

@MainActor
public final class BackendStatusModel: ObservableObject {
    @Published public private(set) var workspace: Workspace?
    @Published public private(set) var workspaces: [Workspace] = []
    @Published public private(set) var auth: AuthStatus?
    @Published public private(set) var sync: SyncStatus?
    @Published public private(set) var tasks: [TaskItem] = []
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var taskActionErrors: [TaskItem.ID: String] = [:]
    @Published public private(set) var isLoading = false

    private let client: any AgendumBackendServicing
    private let syncPollIntervalNanoseconds: UInt64
    private let maxSyncPollAttempts: Int
    private let sleep: @Sendable (UInt64) async throws -> Void

    public convenience init() {
        self.init(client: AgendumBackendClient())
    }

    init(
        client: any AgendumBackendServicing,
        syncPollIntervalNanoseconds: UInt64 = 500_000_000,
        maxSyncPollAttempts: Int = 120,
        sleep: @escaping @Sendable (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) }
    ) {
        self.client = client
        self.syncPollIntervalNanoseconds = syncPollIntervalNanoseconds
        self.maxSyncPollAttempts = maxSyncPollAttempts
        self.sleep = sleep
    }

    public var workspaceLabel: String {
        workspace?.displayName ?? "Loading workspace"
    }

    public var selectedWorkspaceID: String {
        workspace?.id ?? "base"
    }

    public var authLabel: String {
        guard let auth else {
            return "Checking GitHub auth"
        }
        if auth.authenticated {
            return auth.username.map { "GitHub: \($0)" } ?? "GitHub authenticated"
        }
        if auth.ghFound {
            return "GitHub auth needed"
        }
        return "GitHub CLI missing"
    }

    public var syncLabel: String {
        guard let sync else {
            return "Sync status unknown"
        }
        if let lastError = sync.lastError {
            return "Sync \(sync.state): \(lastError)"
        }
        if sync.changes > 0 {
            return "Sync \(sync.state): \(sync.changes) changes"
        }
        return "Sync \(sync.state)"
    }

    public func errorForTask(id: TaskItem.ID) -> String? {
        taskActionErrors[id]
    }

    public func refresh() async {
        isLoading = true
        defer { isLoading = false }

        do {
            workspace = try await client.currentWorkspace()
            workspaces = try await client.listWorkspaces()
            auth = try await client.authStatus()
            sync = try await client.syncStatus()
            tasks = try await loadTaskItems()
            errorMessage = nil
            taskActionErrors = [:]
        } catch {
            tasks = []
            taskActionErrors = [:]
            errorMessage = String(describing: error)
        }
    }

    public func selectWorkspace(id: String) async {
        guard id != selectedWorkspaceID, let target = workspaces.first(where: { $0.id == id }) else {
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let selection = try await client.selectWorkspace(namespace: target.namespace)
            workspace = selection.workspace
            auth = selection.auth
            sync = selection.sync
            workspaces = try await client.listWorkspaces()
            tasks = []
            tasks = try await loadTaskItems()
            errorMessage = nil
            taskActionErrors = [:]
        } catch {
            tasks = []
            taskActionErrors = [:]
            errorMessage = String(describing: error)
        }
    }

    public func forceSync() async {
        isLoading = true
        defer { isLoading = false }

        do {
            sync = try await client.forceSync()
            try await pollSyncUntilComplete()
            tasks = try await loadTaskItems()
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    public func markSeen(id: TaskItem.ID) async {
        await performTaskAction(taskID: id) {
            _ = try await client.markTaskSeen(id: id)
        }
    }

    public func markReviewed(id: TaskItem.ID) async {
        await performTaskAction(taskID: id) {
            _ = try await client.markTaskReviewed(id: id)
        }
    }

    public func markInProgress(id: TaskItem.ID) async {
        await performTaskAction(taskID: id) {
            _ = try await client.markTaskInProgress(id: id)
        }
    }

    public func moveToBacklog(id: TaskItem.ID) async {
        await performTaskAction(taskID: id) {
            _ = try await client.moveTaskToBacklog(id: id)
        }
    }

    public func markDone(id: TaskItem.ID) async {
        await performTaskAction(taskID: id) {
            _ = try await client.markTaskDone(id: id)
        }
    }

    public func removeTask(id: TaskItem.ID) async {
        await performTaskAction(taskID: id) {
            _ = try await client.removeTask(id: id)
        }
    }

    @discardableResult
    public func createManualTask(
        title: String,
        project: String? = nil,
        tags: [String]? = nil
    ) async -> Bool {
        isLoading = true
        defer { isLoading = false }

        do {
            _ = try await client.createManualTask(title: title, project: project, tags: tags)
            tasks = try await loadTaskItems()
            errorMessage = nil
            return true
        } catch {
            errorMessage = String(describing: error)
            return false
        }
    }

    private func performTaskAction(taskID: TaskItem.ID, _ action: () async throws -> Void) async {
        isLoading = true
        defer { isLoading = false }

        do {
            try await action()
            tasks = try await loadTaskItems()
            taskActionErrors.removeValue(forKey: taskID)
            errorMessage = nil
        } catch {
            taskActionErrors[taskID] = String(describing: error)
        }
    }

    private func pollSyncUntilComplete() async throws {
        var attempts = 0
        while sync?.state == "running", attempts < maxSyncPollAttempts {
            try await sleep(syncPollIntervalNanoseconds)
            sync = try await client.syncStatus()
            attempts += 1
        }
    }

    private func loadTaskItems() async throws -> [TaskItem] {
        try await client.listTasks(
            source: nil,
            status: nil,
            project: nil,
            includeSeen: true,
            limit: 50
        ).map(TaskItem.init)
    }
}
