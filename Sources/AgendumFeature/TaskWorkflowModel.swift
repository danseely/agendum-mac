import AgendumModel
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

public protocol DashboardServicing: Sendable {
    func currentWorkspace() async throws -> Workspace
    func listWorkspaces() async throws -> [Workspace]
    func selectWorkspace(namespace: String?) async throws -> WorkspaceSelection
    func syncStatus() async throws -> SyncStatus
    func forceSync() async throws -> SyncStatus
    func authStatus() async throws -> AuthStatus
    func authDiagnose() async throws -> AuthDiagnostics
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

extension TaskItem {
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
    public func perform(on model: DashboardModel) async {
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
    public func availability(on model: DashboardModel) -> Bool {
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
        on model: DashboardModel
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
        if let dashboardError = error as? DashboardServiceError {
            return PresentedError(
                message: dashboardError.message,
                recovery: dashboardError.recovery,
                code: dashboardError.code
            )
        }
        if let modelError = error as? DashboardModelError {
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

public struct DashboardServiceError: Error, Equatable, Sendable {
    public let code: String
    public let message: String
    public let recovery: String?

    public init(code: String, message: String, recovery: String? = nil) {
        self.code = code
        self.message = message
        self.recovery = recovery
    }
}

/// Factory invoked by `DashboardModel` to create a `TaskStoreProviding` for a
/// given on-disk database URL. Production passes `{ try TaskStore(path: $0) }`;
/// tests pass `{ _ in fakeStore }`.
public typealias TaskStoreFactory = @Sendable (URL) throws -> any TaskStoreProviding

public enum DashboardModelError: Error, Equatable, Sendable {
    /// A task action ran before `refresh()` populated the workspace and store.
    case storeNotReady
}

@Observable
@MainActor
public final class DashboardModel {
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

    private let service: any DashboardServicing
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
        service: any DashboardServicing,
        openURL: @escaping URLOpening,
        pasteboard: @escaping Pasteboarding,
        notifier: @escaping Notifying,
        setBadge: @escaping BadgeSetting,
        storeFactory: @escaping TaskStoreFactory
    ) {
        self.init(
            service: service,
            storeFactory: storeFactory,
            openURL: openURL,
            pasteboard: pasteboard,
            notifier: notifier,
            setBadge: setBadge
        )
    }

    init(
        service: any DashboardServicing,
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
        self.service = service
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
        logger.notice("DashboardModel.refresh start")
        isLoading = true
        defer { isLoading = false }

        do {
            workspace = try await service.currentWorkspace()
            workspaces = try await service.listWorkspaces()
            auth = try await service.authStatus()
            sync = try await service.syncStatus()
            try updateStoreIfNeeded(workspace: workspace)
            tasks = try await loadTaskItems()
            self.error = nil
            taskActionErrors = [:]
            logger.notice("DashboardModel.refresh ok: \(self.tasks.count, privacy: .public) tasks")
        } catch {
            tasks = []
            taskActionErrors = [:]
            let presented = PresentedError.from(error)
            self.error = presented
            logger.error("DashboardModel.refresh failed: code=\(presented.code ?? "nil", privacy: .public) message=\(presented.message, privacy: .public)")
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

        logger.notice("DashboardModel.selectWorkspace start: id=\(id, privacy: .public)")
        isLoading = true
        defer { isLoading = false }

        do {
            let selection = try await service.selectWorkspace(namespace: target.namespace)
            workspace = selection.workspace
            auth = selection.auth
            sync = selection.sync
            workspaces = try await service.listWorkspaces()
            filters = .default
            tasks = []
            try updateStoreIfNeeded(workspace: workspace)
            tasks = try await loadTaskItems()
            self.error = nil
            taskActionErrors = [:]
            logger.notice("DashboardModel.selectWorkspace ok: id=\(id, privacy: .public)")
        } catch {
            filters = .default
            tasks = []
            taskActionErrors = [:]
            let presented = PresentedError.from(error)
            self.error = presented
            logger.error("DashboardModel.selectWorkspace failed: id=\(id, privacy: .public) code=\(presented.code ?? "nil", privacy: .public) message=\(presented.message, privacy: .public)")
        }
    }

    public func forceSync() async {
        logger.notice("DashboardModel.forceSync start")
        isLoading = true
        defer { isLoading = false }
        var didReceiveForceSyncStatus = false

        do {
            sync = try await service.forceSync()
            didReceiveForceSyncStatus = true
            try await pollSyncUntilComplete()
            tasks = try await loadTaskItems()
            self.error = nil
            logger.notice("DashboardModel.forceSync state=\(self.sync?.state ?? "unknown", privacy: .public) changes=\(self.sync?.changes ?? 0, privacy: .public)")
            if sync?.state == "error" {
                // Backend-reported error path: forceSync did not throw, but
                // sync.state == "error". Route through the shared notification
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
            if !didReceiveForceSyncStatus,
               let latestSync = try? await service.syncStatus() {
                sync = latestSync
            }
            let presented = PresentedError.from(error)
            self.error = presented
            logger.error("DashboardModel.forceSync failed: code=\(presented.code ?? "nil", privacy: .public) message=\(presented.message, privacy: .public)")
            if let code = presented.code,
               code.contains("auth") || code.contains("token") {
                logger.notice("DashboardModel.forceSync auth/token invalidation surfaced: code=\(code, privacy: .public)")
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
        logger.notice("DashboardModel.openTaskURL start: id=\(id, privacy: .public)")
        guard let task = tasks.first(where: { $0.id == id }) else {
            // Unknown task ID: return without mutating taskActionErrors.
            // No view can read or clear a stale entry under an id that does
            // not correspond to a visible task, so writing one would leak
            // state.
            logger.error("DashboardModel.openTaskURL unknown id=\(id, privacy: .public)")
            return
        }
        guard let url = task.url else {
            taskActionErrors[id] = PresentedError(
                message: "This task has no URL to open.",
                recovery: "Manual tasks have no link; remove them or add a URL upstream.",
                code: "client.taskHasNoURL"
            )
            logger.error("DashboardModel.openTaskURL no URL: id=\(id, privacy: .public)")
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
            logger.error("DashboardModel.openTaskURL failed to open URL for id=\(id, privacy: .public)")
        }
    }

    public func refreshDiagnostics() async {
        do {
            let result = try await service.authDiagnose()
            diagnostics = result
            diagnosticsError = nil
        } catch {
            let presented = PresentedError.from(error)
            diagnosticsError = presented
            logger.error("DashboardModel.refreshDiagnostics failed: code=\(presented.code ?? "nil", privacy: .public) message=\(presented.message, privacy: .public)")
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
        logger.notice("DashboardModel.createManualTask start")
        isLoading = true
        defer { isLoading = false }

        do {
            _ = try await requireStore().createManualTask(title: title, project: project, tags: tags)
            tasks = try await loadTaskItems()
            self.error = nil
            logger.notice("DashboardModel.createManualTask ok")
            return true
        } catch {
            let presented = PresentedError.from(error)
            self.error = presented
            logger.error("DashboardModel.createManualTask failed: code=\(presented.code ?? "nil", privacy: .public) message=\(presented.message, privacy: .public)")
            return false
        }
    }

    private func performTaskAction(name: String, taskID: TaskItem.ID, _ action: () async throws -> Void) async {
        logger.notice("DashboardModel.\(name, privacy: .public) start: id=\(taskID, privacy: .public)")
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
            logger.error("DashboardModel.\(name, privacy: .public) failed: id=\(taskID, privacy: .public) code=\(presented.code ?? "nil", privacy: .public) message=\(presented.message, privacy: .public)")
        }
    }

    private func pollSyncUntilComplete() async throws {
        var attempts = 0
        while sync?.state == "running", attempts < maxSyncPollAttempts {
            try await sleep(syncPollIntervalNanoseconds)
            sync = try await service.syncStatus()
            attempts += 1
        }
    }

    private func loadTaskItems() async throws -> [TaskItem] {
        try await requireStore().tasks(matching: filters)
    }
}
