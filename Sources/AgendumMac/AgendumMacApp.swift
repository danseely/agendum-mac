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
    let isUnseen: Bool
}

private enum TaskSource: String, CaseIterable, Identifiable {
    case authored = "My Pull Requests"
    case review = "Reviews Requested"
    case issues = "Issues & Manual"

    var id: String { rawValue }
}

private struct TaskDashboardView: View {
    @State private var selection: TaskSource? = .authored
    @State private var selectedTask: TaskItem.ID?
    @StateObject private var backendStatus = BackendStatusModel()

    private let tasks: [TaskItem] = [
        .init(
            id: 1,
            title: "Add review-thread resolution tracking",
            source: .authored,
            status: "review received",
            project: "agendum",
            author: nil,
            number: 42,
            isUnseen: true
        ),
        .init(
            id: 2,
            title: "Review release workflow hardening",
            source: .review,
            status: "review requested",
            project: "homebrew-tap",
            author: "Morgan",
            number: 17,
            isUnseen: true
        ),
        .init(
            id: 3,
            title: "Sketch Mac backend contract",
            source: .issues,
            status: "backlog",
            project: "agendum-mac",
            author: nil,
            number: nil,
            isUnseen: false
        ),
    ]

    var body: some View {
        NavigationSplitView {
            List(TaskSource.allCases, selection: $selection) { source in
                Label(source.rawValue, systemImage: icon(for: source))
                    .badge(tasks.filter { $0.source == source }.count)
            }
            .navigationTitle("Agendum")
            .safeAreaInset(edge: .bottom) {
                BackendStatusPanel(status: backendStatus)
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
                        Task {
                            await backendStatus.refresh()
                        }
                    } label: {
                        Label("Sync", systemImage: "arrow.clockwise")
                    }
                    .disabled(backendStatus.isLoading)
                }
            }
        } detail: {
            if let task = selectedTask.flatMap(taskByID) {
                TaskDetail(task: task)
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
        tasks.filter { $0.source == selection }
    }

    private func taskByID(_ id: TaskItem.ID) -> TaskItem? {
        tasks.first { $0.id == id }
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
    @Published var auth: AuthStatus?
    @Published var errorMessage: String?
    @Published var isLoading = false

    private let client = AgendumBackendClient()

    var workspaceLabel: String {
        workspace?.displayName ?? "Loading workspace"
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

    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        do {
            workspace = try await client.currentWorkspace()
            auth = try await client.authStatus()
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }
}

private struct BackendStatusPanel: View {
    @ObservedObject var status: BackendStatusModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(status.workspaceLabel, systemImage: "folder")
                    .lineLimit(1)
                Spacer()
                if status.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Label(status.authLabel, systemImage: status.auth?.authenticated == true ? "checkmark.seal" : "exclamationmark.triangle")
                .foregroundStyle(status.auth?.authenticated == true ? Color.secondary : Color.orange)
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
    let task: TaskItem

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
                Button("Open in Browser") {}
                Button("Mark Done") {}
                Button("Remove") {}
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
