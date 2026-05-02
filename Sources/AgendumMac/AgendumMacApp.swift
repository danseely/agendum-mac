import AgendumMacWorkflow
import SwiftUI

@main
struct AgendumMacApp: App {
    @StateObject private var backendStatus = BackendStatusModel()
    private let commands = TaskDashboardCommands.standard

    var body: some Scene {
        WindowGroup {
            TaskDashboardView(backendStatus: backendStatus, commands: commands)
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Sync Now") {
                    Task {
                        await commands.menuSync.perform(on: backendStatus)
                    }
                }
                    .keyboardShortcut("r", modifiers: [.command])
                    .disabled(backendStatus.isLoading)
            }
        }

        Settings {
            SettingsView()
        }
    }
}

private struct TaskDashboardView: View {
    @State private var selection: TaskSource? = .authored
    @State private var selectedTask: TaskItem.ID?
    @ObservedObject var backendStatus: BackendStatusModel
    let commands: TaskDashboardCommands

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
                            await commands.toolbarRefresh.perform(on: backendStatus)
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
                            await commands.toolbarSync.perform(on: backendStatus)
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
                if task.availableDetailActions.contains(.openBrowser) {
                    Button("Open in Browser") {
                        if let url = task.url {
                            openURL(url)
                        }
                    }
                }
                if task.availableDetailActions.contains(.markSeen) {
                    Button("Mark Seen") {
                        Task {
                            await markSeen()
                        }
                    }
                    .disabled(isLoading)
                }
                if task.availableDetailActions.contains(.markReviewed) {
                    Button("Mark Reviewed") {
                        Task {
                            await markReviewed()
                        }
                    }
                    .disabled(isLoading)
                }
                if task.availableDetailActions.contains(.moveToBacklog) {
                    Button("Move to Backlog") {
                        Task {
                            await moveToBacklog()
                        }
                    }
                    .disabled(isLoading)
                }
                if task.availableDetailActions.contains(.markInProgress) {
                    Button("Mark In Progress") {
                        Task {
                            await markInProgress()
                        }
                    }
                    .disabled(isLoading)
                }
                if task.availableDetailActions.contains(.markDone) {
                    Button("Mark Done") {
                        Task {
                            await markDone()
                        }
                    }
                    .disabled(isLoading)
                }
                if task.availableDetailActions.contains(.remove) {
                    Button("Remove") {
                        Task {
                            await remove()
                        }
                    }
                    .disabled(isLoading)
                }
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
