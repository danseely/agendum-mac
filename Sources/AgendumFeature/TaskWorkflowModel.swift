import AgendumBackend
import Foundation
import Observation

public typealias URLOpening = @Sendable (URL) -> Bool
public typealias Pasteboarding = @Sendable (String) -> Void
public typealias Notifying = @Sendable (NotificationContent) async -> Void
public typealias BadgeSetting = @Sendable (Int) -> Void

public struct NotificationContent: Equatable, Sendable {
    public let identifier: String
    public let title: String
    public let body: String

    public init(identifier: String, title: String, body: String) {
        self.identifier = identifier
        self.title = title
        self.body = body
    }
}

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
    func authDiagnose() async throws -> AuthDiagnostics
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
        project = task.project ?? task.ghRepo ?? "No project"
        author = task.ghAuthorName ?? task.ghAuthor
        number = task.ghNumber
        url = task.ghUrl.flatMap(URL.init(string:))
        isUnseen = !task.seen
    }

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
    case newTask
    case openInBrowser
    case markSeen
    case markReviewed
    case markInProgress
    case moveToBacklog
    case markDone
    case remove

    @MainActor
    public func perform(on model: BackendStatusModel) async {
        switch self {
        case .refresh:
            await model.refresh()
        case .sync:
            await model.forceSync()
        case .newTask:
            // Sheet presentation lives in SwiftUI; the command is a no-op
            // when invoked directly. The SwiftUI layer reads
            // `commands.menuNewTask` only as an availability + identifier
            // descriptor and triggers the sheet via a separate @State.
            return
        case .openInBrowser:
            guard let id = model.selectedTaskID else { return }
            await model.openTaskURL(id: id)
        case .markSeen:
            guard let id = model.selectedTaskID else { return }
            await model.markSeen(id: id)
        case .markReviewed:
            guard let id = model.selectedTaskID else { return }
            await model.markReviewed(id: id)
        case .markInProgress:
            guard let id = model.selectedTaskID else { return }
            await model.markInProgress(id: id)
        case .moveToBacklog:
            guard let id = model.selectedTaskID else { return }
            await model.moveToBacklog(id: id)
        case .markDone:
            guard let id = model.selectedTaskID else { return }
            await model.markDone(id: id)
        case .remove:
            guard let id = model.selectedTaskID else { return }
            await model.removeTask(id: id)
        }
    }

    @MainActor
    public func availability(on model: BackendStatusModel) -> Bool {
        switch self {
        case .refresh, .sync, .newTask:
            return !model.isLoading
        case .openInBrowser:
            return perTaskAvailable(.openBrowser, on: model)
        case .markSeen:
            return perTaskAvailable(.markSeen, on: model)
        case .markReviewed:
            return perTaskAvailable(.markReviewed, on: model)
        case .markInProgress:
            return perTaskAvailable(.markInProgress, on: model)
        case .moveToBacklog:
            return perTaskAvailable(.moveToBacklog, on: model)
        case .markDone:
            return perTaskAvailable(.markDone, on: model)
        case .remove:
            return perTaskAvailable(.remove, on: model)
        }
    }

    @MainActor
    private func perTaskAvailable(
        _ action: TaskDetailAction,
        on model: BackendStatusModel
    ) -> Bool {
        // Block per-task actions while a workspace switch / refresh / force-sync
        // is in flight. Otherwise a click during `await client.selectWorkspace`
        // would write to the OUTGOING workspace's database via the still-bound
        // store. Blanket isLoading check is the simplest fix; finer-grained
        // gating can come later if needed.
        guard !model.isLoading else { return false }
        guard
            let id = model.selectedTaskID,
            let task = model.tasks.first(where: { $0.id == id })
        else {
            return false
        }
        return task.availableDetailActions.contains(action)
    }
}

public struct TaskDashboardCommands: Equatable, Sendable {
    public let toolbarRefresh: TaskDashboardCommand
    public let toolbarSync: TaskDashboardCommand
    public let menuRefresh: TaskDashboardCommand
    public let menuSync: TaskDashboardCommand
    public let menuNewTask: TaskDashboardCommand
    public let menuOpenInBrowser: TaskDashboardCommand
    public let menuMarkSeen: TaskDashboardCommand
    public let menuMarkReviewed: TaskDashboardCommand
    public let menuMarkInProgress: TaskDashboardCommand
    public let menuMoveToBacklog: TaskDashboardCommand
    public let menuMarkDone: TaskDashboardCommand
    public let menuRemove: TaskDashboardCommand

    public static let standard = TaskDashboardCommands(
        toolbarRefresh: .refresh,
        toolbarSync: .sync,
        menuRefresh: .refresh,
        menuSync: .sync,
        menuNewTask: .newTask,
        menuOpenInBrowser: .openInBrowser,
        menuMarkSeen: .markSeen,
        menuMarkReviewed: .markReviewed,
        menuMarkInProgress: .markInProgress,
        menuMoveToBacklog: .moveToBacklog,
        menuMarkDone: .markDone,
        menuRemove: .remove
    )
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
        if let modelError = error as? BackendStatusModelError {
            switch modelError {
            case .storeNotReady:
                return PresentedError(
                    message: "Workspace database is not ready yet.",
                    recovery: "Refresh the dashboard, then try again.",
                    code: "store.notReady"
                )
            }
        }
        return PresentedError(message: String(describing: error), recovery: nil, code: "client.unknown")
    }
}

/// Factory invoked by `BackendStatusModel` to create a `TaskStoreProviding` for a
/// given on-disk database URL. Production passes `{ try TaskStore(path: $0) }`;
/// tests pass `{ _ in fakeStore }`.
public typealias TaskStoreFactory = @Sendable (URL) throws -> any TaskStoreProviding

public enum BackendStatusModelError: Error, Equatable, Sendable {
    /// A task action ran before `refresh()` populated the workspace and store.
    case storeNotReady
}

@Observable
@MainActor
public final class BackendStatusModel {
    public private(set) var workspace: Workspace?
    public private(set) var workspaces: [Workspace] = []
    public private(set) var auth: AuthStatus?
    public private(set) var sync: SyncStatus?
    public private(set) var tasks: [TaskItem] = []
    public private(set) var error: PresentedError?
    public private(set) var taskActionErrors: [TaskItem.ID: PresentedError] = [:]
    public private(set) var filters: TaskListFilters = .default
    public private(set) var isLoading = false
    public private(set) var diagnostics: AuthDiagnostics?
    public private(set) var diagnosticsError: PresentedError?
    public internal(set) var selectedTaskID: TaskItem.ID?

    public func setSelectedTaskID(_ id: TaskItem.ID?) {
        selectedTaskID = id
    }

    public func restoreSceneState(filters: TaskListFilters, selectedTaskID: TaskItem.ID?) {
        self.filters = filters
        self.selectedTaskID = selectedTaskID
    }

    public var errorMessage: String? { error?.message }

    private let client: any AgendumBackendServicing
    /// Factory invoked when the workspace's `dbPath` first becomes known (in `refresh()`)
    /// or changes (in `selectWorkspace(...)`). Tests inject a closure returning a
    /// `FakeTaskStore`; production injects `{ try TaskStore(path: $0) }`.
    private let storeFactory: TaskStoreFactory
    private var store: (any TaskStoreProviding)?
    private var currentStorePath: String?
    private let syncPollIntervalNanoseconds: UInt64
    private let maxSyncPollAttempts: Int
    private let sleep: @Sendable (UInt64) async throws -> Void
    private let now: @Sendable () -> Date
    private let openURL: URLOpening
    private let pasteboard: Pasteboarding
    private let notifier: Notifying
    private let setBadge: BadgeSetting
    private let relativeFormatter: RelativeDateTimeFormatter
    private let iso8601Formatter: ISO8601DateFormatter

    public convenience init(
        openURL: @escaping URLOpening,
        pasteboard: @escaping Pasteboarding,
        notifier: @escaping Notifying,
        setBadge: @escaping BadgeSetting,
        storeFactory: @escaping TaskStoreFactory
    ) {
        self.init(
            client: AgendumBackendClient(),
            storeFactory: storeFactory,
            openURL: openURL,
            pasteboard: pasteboard,
            notifier: notifier,
            setBadge: setBadge
        )
    }

    init(
        client: any AgendumBackendServicing,
        storeFactory: @escaping TaskStoreFactory,
        syncPollIntervalNanoseconds: UInt64 = 500_000_000,
        maxSyncPollAttempts: Int = 120,
        sleep: @escaping @Sendable (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) },
        now: @escaping @Sendable () -> Date = Date.init,
        openURL: @escaping URLOpening = { _ in false },
        pasteboard: @escaping Pasteboarding = { _ in },
        notifier: @escaping Notifying = { _ in },
        setBadge: @escaping BadgeSetting = { _ in },
        locale: Locale = .autoupdatingCurrent,
        filters: TaskListFilters = .default
    ) {
        self.client = client
        self.storeFactory = storeFactory
        self.syncPollIntervalNanoseconds = syncPollIntervalNanoseconds
        self.maxSyncPollAttempts = maxSyncPollAttempts
        self.sleep = sleep
        self.now = now
        self.openURL = openURL
        self.pasteboard = pasteboard
        self.notifier = notifier
        self.setBadge = setBadge
        self.filters = filters
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .short
        self.relativeFormatter = formatter
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        self.iso8601Formatter = iso
    }

    /// Reconciles the active store against the current workspace's `dbPath`.
    /// Creates a new `TaskStoreProviding` instance only when the path actually changes.
    private func updateStoreIfNeeded(workspace: Workspace?) throws {
        guard let workspace else { return }
        if currentStorePath == workspace.dbPath { return }
        let url = URL(fileURLWithPath: workspace.dbPath)
        store = try storeFactory(url)
        currentStorePath = workspace.dbPath
    }

    /// Returns the current `TaskStoreProviding` instance, lazily initializing it from
    /// the active workspace's `dbPath` (or a default path when no workspace has been
    /// fetched yet — this happens in tests that exercise task actions without first
    /// calling `refresh()`).
    private func requireStore() throws -> any TaskStoreProviding {
        if let store { return store }
        let path = workspace?.dbPath ?? Self.defaultStorePath
        let url = URL(fileURLWithPath: path)
        let new = try storeFactory(url)
        store = new
        currentStorePath = path
        return new
    }

    private static let defaultStorePath: String = {
        NSHomeDirectory() + "/.agendum/agendum.db"
    }()

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

    public var attentionItemCount: Int {
        // Today the backend payload exposes a boolean (hasAttentionItems);
        // tomorrow it may carry an explicit integer. The accessor adapts so
        // the SwiftUI .onChange wiring doesn't need to know.
        return hasAttentionItems ? 1 : 0
    }

    public func setBadgeForAttentionCount() {
        setBadge(attentionItemCount)
    }

    public func errorForTask(id: TaskItem.ID) -> PresentedError? {
        taskActionErrors[id]
    }

    public func refresh() async {
        logger.notice("BackendStatusModel.refresh start")
        isLoading = true
        defer { isLoading = false }

        do {
            workspace = try await client.currentWorkspace()
            workspaces = try await client.listWorkspaces()
            auth = try await client.authStatus()
            sync = try await client.syncStatus()
            try updateStoreIfNeeded(workspace: workspace)
            tasks = try await loadTaskItems()
            self.error = nil
            taskActionErrors = [:]
            logger.notice("BackendStatusModel.refresh ok: \(self.tasks.count, privacy: .public) tasks")
        } catch {
            tasks = []
            taskActionErrors = [:]
            let presented = PresentedError.from(error)
            self.error = presented
            logger.error("BackendStatusModel.refresh failed: code=\(presented.code ?? "nil", privacy: .public) message=\(presented.message, privacy: .public)")
        }
    }

    public func applyFilters(_ filters: TaskListFilters) async {
        guard self.filters != filters else { return }
        self.filters = filters
        await refresh()
    }

    public func selectWorkspace(id: String) async {
        guard id != selectedWorkspaceID, let target = workspaces.first(where: { $0.id == id }) else {
            return
        }

        logger.notice("BackendStatusModel.selectWorkspace start: id=\(id, privacy: .public)")
        isLoading = true
        defer { isLoading = false }

        do {
            let selection = try await client.selectWorkspace(namespace: target.namespace)
            workspace = selection.workspace
            auth = selection.auth
            sync = selection.sync
            workspaces = try await client.listWorkspaces()
            filters = .default
            tasks = []
            try updateStoreIfNeeded(workspace: workspace)
            tasks = try await loadTaskItems()
            self.error = nil
            taskActionErrors = [:]
            logger.notice("BackendStatusModel.selectWorkspace ok: id=\(id, privacy: .public)")
        } catch {
            filters = .default
            tasks = []
            taskActionErrors = [:]
            let presented = PresentedError.from(error)
            self.error = presented
            logger.error("BackendStatusModel.selectWorkspace failed: id=\(id, privacy: .public) code=\(presented.code ?? "nil", privacy: .public) message=\(presented.message, privacy: .public)")
        }
    }

    public func forceSync() async {
        logger.notice("BackendStatusModel.forceSync start")
        isLoading = true
        defer { isLoading = false }

        do {
            sync = try await client.forceSync()
            try await pollSyncUntilComplete()
            tasks = try await loadTaskItems()
            self.error = nil
            logger.notice("BackendStatusModel.forceSync state=\(self.sync?.state ?? "unknown", privacy: .public) changes=\(self.sync?.changes ?? 0, privacy: .public)")
            if sync?.state == "error" {
                // Backend-reported error path: forceSync did not throw, but
                // sync.state == "error". Route through the shared helper
                // by synthesizing a PresentedError so the failure-body
                // template lives in exactly one place. Do NOT clobber
                // self.error: branch (b) deliberately leaves the model's
                // structured-error surface untouched (see design §3.5).
                let suffix = sync?.lastError ?? "Unknown error."
                await postSyncCompletedNotification(
                    success: false,
                    failure: PresentedError(message: suffix)
                )
            } else {
                await postSyncCompletedNotification(success: true, failure: nil)
            }
        } catch {
            let presented = PresentedError.from(error)
            self.error = presented
            if case BackendClientError.requestTimedOut = error {
                logger.error("BackendStatusModel.forceSync timed out: \(presented.message, privacy: .public)")
            } else {
                logger.error("BackendStatusModel.forceSync failed: code=\(presented.code ?? "nil", privacy: .public) message=\(presented.message, privacy: .public)")
            }
            if let code = presented.code,
               code.contains("auth") || code.contains("token") {
                logger.notice("BackendStatusModel.forceSync auth/token invalidation surfaced: code=\(code, privacy: .public)")
            }
            await postSyncCompletedNotification(success: false, failure: presented)
        }
    }

    private func postSyncCompletedNotification(
        success: Bool,
        failure: PresentedError?
    ) async {
        let body: String
        if success {
            let count = attentionItemCount
            if count > 0 {
                body = "Sync complete. \(count) attention item\(count == 1 ? "" : "s")."
            } else {
                body = "Sync complete."
            }
        } else {
            let suffix = failure?.message ?? "Unknown error."
            body = "Sync failed: \(suffix)"
        }
        // Shared identifier across success and failure shapes so macOS
        // coalesces repeated banners (the user sees the latest, not a
        // stack of N).
        await notifier(NotificationContent(
            identifier: "agendum.sync.completed",
            title: "Agendum",
            body: body
        ))
    }

    public func markSeen(id: TaskItem.ID) async {
        await performTaskAction(name: "markSeen", taskID: id) { [self] in
            try await requireStore().markSeen(id: id)
        }
    }

    public func markReviewed(id: TaskItem.ID) async {
        await performTaskAction(name: "markReviewed", taskID: id) { [self] in
            try await requireStore().updateTaskStatus(id: id, status: "reviewed")
        }
    }

    public func markInProgress(id: TaskItem.ID) async {
        await performTaskAction(name: "markInProgress", taskID: id) { [self] in
            try await requireStore().updateTaskStatus(id: id, status: "in progress")
        }
    }

    public func moveToBacklog(id: TaskItem.ID) async {
        await performTaskAction(name: "moveToBacklog", taskID: id) { [self] in
            try await requireStore().updateTaskStatus(id: id, status: "backlog")
        }
    }

    public func markDone(id: TaskItem.ID) async {
        await performTaskAction(name: "markDone", taskID: id) { [self] in
            try await requireStore().updateTaskStatus(id: id, status: "done")
        }
    }

    public func removeTask(id: TaskItem.ID) async {
        await performTaskAction(name: "removeTask", taskID: id) { [self] in
            try await requireStore().removeTask(id: id)
        }
    }

    public func openTaskURL(id: TaskItem.ID) async {
        logger.notice("BackendStatusModel.openTaskURL start: id=\(id, privacy: .public)")
        guard let task = tasks.first(where: { $0.id == id }) else {
            // Unknown task ID: return without mutating taskActionErrors.
            // No view can read or clear a stale entry under an id that does
            // not correspond to a visible task, so writing one would leak
            // state.
            logger.error("BackendStatusModel.openTaskURL unknown id=\(id, privacy: .public)")
            return
        }
        guard let url = task.url else {
            taskActionErrors[id] = PresentedError(
                message: "This task has no URL to open.",
                recovery: "Manual tasks have no link; remove them or add a URL upstream.",
                code: "client.taskHasNoURL"
            )
            logger.error("BackendStatusModel.openTaskURL no URL: id=\(id, privacy: .public)")
            return
        }
        let opened = openURL(url)
        if opened {
            taskActionErrors.removeValue(forKey: id)
        } else {
            taskActionErrors[id] = PresentedError(
                message: "Could not open the task URL in a browser.",
                recovery: "Check that a default browser is set, then try again.",
                code: "client.urlOpenFailed"
            )
            logger.error("BackendStatusModel.openTaskURL failed to open URL for id=\(id, privacy: .public)")
        }
    }

    public func refreshDiagnostics() async {
        do {
            let result = try await client.authDiagnose()
            diagnostics = result
            diagnosticsError = nil
        } catch {
            let presented = PresentedError.from(error)
            diagnosticsError = presented
            logger.error("BackendStatusModel.refreshDiagnostics failed: code=\(presented.code ?? "nil", privacy: .public) message=\(presented.message, privacy: .public)")
        }
    }

    public func copyAuthLoginCommand() {
        guard let command = auth?.repairCommand else { return }
        pasteboard(command)
    }

    public func openGHInstallURL() {
        let url = URL(string: "https://cli.github.com/")!
        _ = openURL(url)
    }

    @discardableResult
    public func createManualTask(
        title: String,
        project: String? = nil,
        tags: [String]? = nil
    ) async -> Bool {
        logger.notice("BackendStatusModel.createManualTask start")
        isLoading = true
        defer { isLoading = false }

        do {
            _ = try await requireStore().createManualTask(title: title, project: project, tags: tags)
            tasks = try await loadTaskItems()
            self.error = nil
            logger.notice("BackendStatusModel.createManualTask ok")
            return true
        } catch {
            let presented = PresentedError.from(error)
            self.error = presented
            logger.error("BackendStatusModel.createManualTask failed: code=\(presented.code ?? "nil", privacy: .public) message=\(presented.message, privacy: .public)")
            return false
        }
    }

    private func performTaskAction(name: String, taskID: TaskItem.ID, _ action: () async throws -> Void) async {
        logger.notice("BackendStatusModel.\(name, privacy: .public) start: id=\(taskID, privacy: .public)")
        isLoading = true
        defer { isLoading = false }

        do {
            try await action()
            tasks = try await loadTaskItems()
            taskActionErrors.removeValue(forKey: taskID)
            self.error = nil
        } catch {
            let presented = PresentedError.from(error)
            taskActionErrors[taskID] = presented
            logger.error("BackendStatusModel.\(name, privacy: .public) failed: id=\(taskID, privacy: .public) code=\(presented.code ?? "nil", privacy: .public) message=\(presented.message, privacy: .public)")
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
        try await requireStore().tasks(matching: filters)
    }
}
