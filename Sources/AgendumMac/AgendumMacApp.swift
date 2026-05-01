import AgendumMacCore
import SwiftUI

@main
struct AgendumMacApp: App {
    var body: some Scene {
        WindowGroup {
            TaskDashboardView()
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Sync Now") {}
                    .keyboardShortcut("r", modifiers: [.command])
            }
        }

        Settings {
            SettingsView()
        }
    }
}

private struct TaskItem: Identifiable, Hashable {
    let id: Int
    let title: String
    let source: TaskSource
    let status: String
    let project: String
    let author: String?
    let number: Int?
    let url: URL?
    let isUnseen: Bool

    init(task: AgendumTask) {
        id = task.id
        title = task.title
        source = TaskSource(backendSource: task.source)
        status = task.status
        project = task.project ?? "No project"
        author = task.ghAuthorName ?? task.ghAuthor
        number = task.ghNumber
        url = task.ghUrl.flatMap(URL.init(string:))
        isUnseen = !task.seen
    }
}

private enum TaskSource: String, CaseIterable, Identifiable {
    case authored = "My Pull Requests"
    case review = "Reviews Requested"
    case issues = "Issues & Manual"

    var id: String { rawValue }

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

private struct TaskDashboardView: View {
    @State private var selection: TaskSource? = .authored
    @State private var selectedTask: TaskItem.ID?
    @StateObject private var backendStatus = BackendStatusModel()

    var body: some View {
        NavigationSplitView {
            List(TaskSource.allCases, selection: $selection) { source in
                Label(source.rawValue, systemImage: icon(for: source))
                    .badge(backendStatus.tasks.filter { $0.source == source }.count)
            }
            .navigationTitle("Agendum")
            .safeAreaInset(edge: .bottom) {
                BackendStatusPanel(status: backendStatus) {
                    selectedTask = nil
                }
            }
        } content: {
            List(filteredTasks, selection: $selectedTask) { task in
                TaskRow(task: task)
                    .tag(task.id)
            }
            .navigationTitle(selection?.rawValue ?? "Tasks")
            .toolbar {
                ToolbarItem {
                    Button {
                        selectedTask = nil
                        Task {
                            await backendStatus.refresh()
                        }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(backendStatus.isLoading)
                }
                ToolbarItem {
                    Button {
                        selectedTask = nil
                        Task {
                            await backendStatus.forceSync()
                        }
                    } label: {
                        Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(backendStatus.isLoading)
                }
            }
        } detail: {
            if let task = selectedTask.flatMap(taskByID) {
                TaskDetail(
                    task: task,
                    isLoading: backendStatus.isLoading,
                    markSeen: {
                        await backendStatus.markSeen(id: task.id)
                    },
                    markReviewed: {
                        selectedTask = nil
                        await backendStatus.markReviewed(id: task.id)
                    },
                    markInProgress: {
                        await backendStatus.markInProgress(id: task.id)
                    },
                    moveToBacklog: {
                        await backendStatus.moveToBacklog(id: task.id)
                    },
                    markDone: {
                        selectedTask = nil
                        await backendStatus.markDone(id: task.id)
                    },
                    remove: {
                        selectedTask = nil
                        await backendStatus.removeTask(id: task.id)
                    }
                )
            } else {
                ContentUnavailableView(
                    "No Task Selected",
                    systemImage: "checklist",
                    description: Text("Select a task from the list.")
                )
            }
        }
        .task {
            await backendStatus.refresh()
        }
    }

    private var filteredTasks: [TaskItem] {
        backendStatus.tasks.filter { $0.source == selection }
    }

    private func taskByID(_ id: TaskItem.ID) -> TaskItem? {
        backendStatus.tasks.first { $0.id == id }
    }

    private func icon(for source: TaskSource) -> String {
        switch source {
        case .authored:
            "arrow.triangle.pull"
        case .review:
            "person.crop.circle.badge.checkmark"
        case .issues:
            "tray.full"
        }
    }
}

@MainActor
private final class BackendStatusModel: ObservableObject {
    @Published var workspace: Workspace?
    @Published var workspaces: [Workspace] = []
    @Published var auth: AuthStatus?
    @Published var sync: SyncStatus?
    @Published var tasks: [TaskItem] = []
    @Published var errorMessage: String?
    @Published var isLoading = false

    private let client = AgendumBackendClient()

    var workspaceLabel: String {
        workspace?.displayName ?? "Loading workspace"
    }

    var selectedWorkspaceID: String {
        workspace?.id ?? "base"
    }

    var authLabel: String {
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

    var syncLabel: String {
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

    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        do {
            workspace = try await client.currentWorkspace()
            workspaces = try await client.listWorkspaces()
            auth = try await client.authStatus()
            sync = try await client.syncStatus()
            tasks = try await client.listTasks().map(TaskItem.init)
            errorMessage = nil
        } catch {
            tasks = []
            errorMessage = String(describing: error)
        }
    }

    func selectWorkspace(id: String) async {
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
            tasks = try await client.listTasks().map(TaskItem.init)
            errorMessage = nil
        } catch {
            tasks = []
            errorMessage = String(describing: error)
        }
    }

    func forceSync() async {
        isLoading = true
        defer { isLoading = false }

        do {
            sync = try await client.forceSync()
            tasks = try await client.listTasks().map(TaskItem.init)
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func markSeen(id: TaskItem.ID) async {
        await performTaskAction {
            _ = try await client.markTaskSeen(id: id)
        }
    }

    func markReviewed(id: TaskItem.ID) async {
        await performTaskAction {
            _ = try await client.markTaskReviewed(id: id)
        }
    }

    func markInProgress(id: TaskItem.ID) async {
        await performTaskAction {
            _ = try await client.markTaskInProgress(id: id)
        }
    }

    func moveToBacklog(id: TaskItem.ID) async {
        await performTaskAction {
            _ = try await client.moveTaskToBacklog(id: id)
        }
    }

    func markDone(id: TaskItem.ID) async {
        await performTaskAction {
            _ = try await client.markTaskDone(id: id)
        }
    }

    func removeTask(id: TaskItem.ID) async {
        await performTaskAction {
            _ = try await client.removeTask(id: id)
        }
    }

    private func performTaskAction(_ action: () async throws -> Void) async {
        isLoading = true
        defer { isLoading = false }

        do {
            try await action()
            tasks = try await client.listTasks().map(TaskItem.init)
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }
}

private struct BackendStatusPanel: View {
    @ObservedObject var status: BackendStatusModel
    let clearSelectedTask: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Menu {
                    ForEach(status.workspaces, id: \.id) { workspace in
                        Button {
                            clearSelectedTask()
                            Task {
                                await status.selectWorkspace(id: workspace.id)
                            }
                        } label: {
                            Label(
                                workspace.displayName,
                                systemImage: workspace.id == status.selectedWorkspaceID ? "checkmark" : "folder"
                            )
                        }
                    }
                } label: {
                    Label(status.workspaceLabel, systemImage: "folder")
                        .lineLimit(1)
                }
                .menuStyle(.borderlessButton)
                .disabled(status.workspaces.isEmpty || status.isLoading)

                Spacer()
                if status.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Label(status.authLabel, systemImage: status.auth?.authenticated == true ? "checkmark.seal" : "exclamationmark.triangle")
                .foregroundStyle(status.auth?.authenticated == true ? Color.secondary : Color.orange)
                .lineLimit(1)

            Label(status.syncLabel, systemImage: status.sync?.state == "error" ? "exclamationmark.arrow.triangle.2.circlepath" : "arrow.triangle.2.circlepath")
                .foregroundStyle(status.sync?.state == "error" ? Color.red : Color.secondary)
                .lineLimit(1)

            if let errorMessage = status.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(3)
            }
        }
        .font(.caption)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
    }
}

private struct TaskRow: View {
    let task: TaskItem

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(task.isUnseen ? Color.red : Color.clear)
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .lineLimit(2)
                HStack {
                    Text(task.status)
                        .foregroundStyle(.secondary)
                    Text(task.project)
                        .foregroundStyle(.tertiary)
                    if let number = task.number {
                        Text("#\(number)")
                            .foregroundStyle(.tertiary)
                    }
                }
                .font(.caption)
            }
        }
        .padding(.vertical, 3)
    }
}

private struct TaskDetail: View {
    @Environment(\.openURL) private var openURL

    let task: TaskItem
    let isLoading: Bool
    let markSeen: () async -> Void
    let markReviewed: () async -> Void
    let markInProgress: () async -> Void
    let moveToBacklog: () async -> Void
    let markDone: () async -> Void
    let remove: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(task.title)
                .font(.title2)
                .fontWeight(.semibold)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    Text("Status").foregroundStyle(.secondary)
                    Text(task.status)
                }
                GridRow {
                    Text("Project").foregroundStyle(.secondary)
                    Text(task.project)
                }
                if let author = task.author {
                    GridRow {
                        Text("Author").foregroundStyle(.secondary)
                        Text(author)
                    }
                }
            }

            HStack {
                Button("Open in Browser") {
                    if let url = task.url {
                        openURL(url)
                    }
                }
                .disabled(task.url == nil)
                if task.isUnseen {
                    Button("Mark Seen") {
                        Task {
                            await markSeen()
                        }
                    }
                    .disabled(isLoading)
                }
                if task.source == .review {
                    Button("Mark Reviewed") {
                        Task {
                            await markReviewed()
                        }
                    }
                    .disabled(isLoading)
                }
                if task.source == .issues {
                    if task.status == "in progress" {
                        Button("Move to Backlog") {
                            Task {
                                await moveToBacklog()
                            }
                        }
                        .disabled(isLoading)
                    } else {
                        Button("Mark In Progress") {
                            Task {
                                await markInProgress()
                            }
                        }
                        .disabled(isLoading)
                    }
                    Button("Mark Done") {
                        Task {
                            await markDone()
                        }
                    }
                    .disabled(isLoading)
                }
                Button("Remove") {
                    Task {
                        await remove()
                    }
                }
                .disabled(isLoading)
            }

            Spacer()
        }
        .padding(24)
        .frame(minWidth: 340, alignment: .topLeading)
    }
}

private struct SettingsView: View {
    var body: some View {
        Form {
            TextField("GitHub organizations", text: .constant("example-org"))
            TextField("Sync interval", text: .constant("120"))
            Toggle("Mark items seen when app is focused", isOn: .constant(true))
        }
        .padding(20)
        .frame(width: 420)
    }
}
