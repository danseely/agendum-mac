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

public struct PresentedError: Equatable, Sendable {
    public let message: String
    public let recovery: String?
    public let code: String?

    public init(message: String, recovery: String? = nil, code: String? = nil) {
        self.message = message
        self.recovery = recovery
        self.code = code
    }

    public static func from(_ error: any Error) -> PresentedError {
        if let clientError = error as? BackendClientError {
            switch clientError {
            case .helperError(let payload):
                return PresentedError(
                    message: payload.message,
                    recovery: payload.recovery ?? payload.detail,
                    code: payload.code
                )
            case .invalidResponse:
                return PresentedError(
                    message: clientError.description,
                    recovery: "The backend helper returned an unexpected response. Try refreshing; if the problem persists, restart the app.",
                    code: "client.protocolMismatch"
                )
            case .helperTerminated:
                return PresentedError(
                    message: clientError.description,
                    recovery: "The backend helper crashed. The app will relaunch it on the next request — try refreshing.",
                    code: "client.helperTerminated"
                )
            case .requestTimedOut:
                return PresentedError(
                    message: clientError.description,
                    recovery: "The backend helper is unresponsive. Try refreshing; if it keeps timing out, check whether sync is stuck.",
                    code: "client.timeout"
                )
            case .unexpectedResponseID:
                return PresentedError(
                    message: clientError.description,
                    recovery: "The backend helper got out of sync with the app. Try refreshing.",
                    code: "client.protocolMismatch"
                )
            case .unsupportedProtocolVersion:
                return PresentedError(
                    message: clientError.description,
                    recovery: "This app version is incompatible with the installed backend helper. Update the app or the helper.",
                    code: "client.unsupportedProtocolVersion"
                )
            }
        }
        return PresentedError(message: String(describing: error), recovery: nil, code: "client.unknown")
    }
}

@MainActor
public final class BackendStatusModel: ObservableObject {
    @Published public private(set) var workspace: Workspace?
    @Published public private(set) var workspaces: [Workspace] = []
    @Published public private(set) var auth: AuthStatus?
    @Published public private(set) var sync: SyncStatus?
    @Published public private(set) var tasks: [TaskItem] = []
    @Published public private(set) var error: PresentedError?
    @Published public private(set) var taskActionErrors: [TaskItem.ID: PresentedError] = [:]
    @Published public private(set) var isLoading = false

    public var errorMessage: String? { error?.message }

    private let client: any AgendumBackendServicing
    private let syncPollIntervalNanoseconds: UInt64
    private let maxSyncPollAttempts: Int
    private let sleep: @Sendable (UInt64) async throws -> Void
    private let now: @Sendable () -> Date
    private let relativeFormatter: RelativeDateTimeFormatter
    private let iso8601Formatter: ISO8601DateFormatter

    public convenience init() {
        self.init(client: AgendumBackendClient())
    }

    init(
        client: any AgendumBackendServicing,
        syncPollIntervalNanoseconds: UInt64 = 500_000_000,
        maxSyncPollAttempts: Int = 120,
        sleep: @escaping @Sendable (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) },
        now: @escaping @Sendable () -> Date = Date.init,
        locale: Locale = .autoupdatingCurrent
    ) {
        self.client = client
        self.syncPollIntervalNanoseconds = syncPollIntervalNanoseconds
        self.maxSyncPollAttempts = maxSyncPollAttempts
        self.sleep = sleep
        self.now = now
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .short
        self.relativeFormatter = formatter
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        self.iso8601Formatter = iso
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
        if sync.changes > 0 {
            return "Sync \(sync.state): \(sync.changes) changes"
        }
        return "Sync \(sync.state)"
    }

    public var lastSyncLabel: String? {
        guard let lastSyncAt = sync?.lastSyncAt,
              let date = iso8601Formatter.date(from: lastSyncAt) else {
            return nil
        }
        let relative = relativeFormatter.localizedString(for: date, relativeTo: now())
        return "Last synced \(relative)"
    }

    public var hasAttentionItems: Bool {
        sync?.hasAttentionItems ?? false
    }

    public func errorForTask(id: TaskItem.ID) -> PresentedError? {
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
            self.error = nil
            taskActionErrors = [:]
        } catch {
            tasks = []
            taskActionErrors = [:]
            self.error = PresentedError.from(error)
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
            self.error = nil
            taskActionErrors = [:]
        } catch {
            tasks = []
            taskActionErrors = [:]
            self.error = PresentedError.from(error)
        }
    }

    public func forceSync() async {
        isLoading = true
        defer { isLoading = false }

        do {
            sync = try await client.forceSync()
            try await pollSyncUntilComplete()
            tasks = try await loadTaskItems()
            self.error = nil
        } catch {
            self.error = PresentedError.from(error)
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
            self.error = nil
            return true
        } catch {
            self.error = PresentedError.from(error)
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
            self.error = nil
        } catch {
            taskActionErrors[taskID] = PresentedError.from(error)
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
