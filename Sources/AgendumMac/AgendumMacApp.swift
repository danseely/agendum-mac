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
                .environmentObject(backendStatus)
        }
    }
}

private struct TaskDashboardView: View {
    @State private var selection: TaskSource? = .authored
    @State private var selectedTask: TaskItem.ID?
    @State private var isShowingCreateManualTask = false
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
                VStack(spacing: 0) {
                    TaskListFiltersPanel(status: backendStatus)
                    BackendStatusPanel(status: backendStatus) {
                        selectedTask = nil
                    }
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
                        isShowingCreateManualTask = true
                    } label: {
                        Label("New Task", systemImage: "plus")
                    }
                    .disabled(backendStatus.isLoading)
                }
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
            .sheet(isPresented: $isShowingCreateManualTask) {
                CreateManualTaskSheet(
                    isLoading: backendStatus.isLoading,
                    create: { title, project, tags in
                        await backendStatus.createManualTask(
                            title: title,
                            project: project,
                            tags: tags
                        )
                    },
                    dismiss: {
                        isShowingCreateManualTask = false
                    }
                )
            }
        } detail: {
            if let task = selectedTask.flatMap(taskByID) {
                TaskDetail(
                    task: task,
                    isLoading: backendStatus.isLoading,
                    actionError: backendStatus.errorForTask(id: task.id),
                    markSeen: {
                        await backendStatus.markSeen(id: task.id)
                    },
                    markReviewed: {
                        await backendStatus.markReviewed(id: task.id)
                        if backendStatus.errorForTask(id: task.id) == nil {
                            selectedTask = nil
                        }
                    },
                    markInProgress: {
                        await backendStatus.markInProgress(id: task.id)
                    },
                    moveToBacklog: {
                        await backendStatus.moveToBacklog(id: task.id)
                    },
                    markDone: {
                        await backendStatus.markDone(id: task.id)
                        if backendStatus.errorForTask(id: task.id) == nil {
                            selectedTask = nil
                        }
                    },
                    remove: {
                        await backendStatus.removeTask(id: task.id)
                        if backendStatus.errorForTask(id: task.id) == nil {
                            selectedTask = nil
                        }
                    },
                    openInBrowser: {
                        await backendStatus.openTaskURL(id: task.id)
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

private struct TaskListFiltersPanel: View {
    @ObservedObject var status: BackendStatusModel
    @AppStorage("task-list-filters-expanded") private var isExpanded: Bool = true
    @State private var pendingFilters: TaskListFilters = .default

    private static let statusOptions: [String] = [
        "draft",
        "open",
        "awaiting review",
        "changes requested",
        "review received",
        "approved",
        "merged",
        "review requested",
        "reviewed",
        "re-review requested",
        "backlog",
        "in progress",
        "closed",
        "done",
    ]

    private static let sourceOptions: [String] = [
        "pr_authored",
        "pr_review",
        "issue",
        "manual",
    ]

    var body: some View {
        DisclosureGroup("Filters", isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Status", selection: Binding(
                    get: { pendingFilters.status ?? "" },
                    set: { newValue in
                        pendingFilters.status = newValue.isEmpty ? nil : newValue
                    }
                )) {
                    Text("All").tag("")
                    ForEach(Self.statusOptions, id: \.self) { value in
                        Text(value).tag(value)
                    }
                }
                .accessibilityIdentifier("task-list-filter-status")

                Picker("Source", selection: Binding(
                    get: { pendingFilters.source ?? "" },
                    set: { newValue in
                        pendingFilters.source = newValue.isEmpty ? nil : newValue
                    }
                )) {
                    Text("All").tag("")
                    ForEach(Self.sourceOptions, id: \.self) { value in
                        Text(value).tag(value)
                    }
                }
                .accessibilityIdentifier("task-list-filter-source")

                TextField("Project", text: Binding(
                    get: { pendingFilters.project ?? "" },
                    set: { newValue in
                        pendingFilters.project = newValue.isEmpty ? nil : newValue
                    }
                ), prompt: Text("Exact match"))
                    .onSubmit {
                        Task { await status.applyFilters(pendingFilters) }
                    }
                    .accessibilityIdentifier("task-list-filter-project")

                Toggle("Include seen items", isOn: $pendingFilters.includeSeen)
                    .accessibilityIdentifier("task-list-filter-include-seen")

                Picker("Limit", selection: $pendingFilters.limit) {
                    ForEach(TaskListFilters.allowedLimits, id: \.self) { value in
                        Text("\(value)").tag(value)
                    }
                }
                .accessibilityIdentifier("task-list-filter-limit")

                Button("Clear filters") {
                    pendingFilters = .default
                    Task { await status.applyFilters(.default) }
                }
                .accessibilityIdentifier("task-list-filter-clear")
            }
            .padding(.top, 4)
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
        .onAppear {
            pendingFilters = status.filters
        }
        .onChange(of: status.filters) { _, newValue in
            if pendingFilters != newValue {
                pendingFilters = newValue
            }
        }
        .onChange(of: pendingFilters.status) { _, _ in
            Task { await status.applyFilters(pendingFilters) }
        }
        .onChange(of: pendingFilters.source) { _, _ in
            Task { await status.applyFilters(pendingFilters) }
        }
        .onChange(of: pendingFilters.includeSeen) { _, _ in
            Task { await status.applyFilters(pendingFilters) }
        }
        .onChange(of: pendingFilters.limit) { _, _ in
            Task { await status.applyFilters(pendingFilters) }
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

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Label(status.syncLabel, systemImage: status.sync?.state == "error" ? "exclamationmark.arrow.triangle.2.circlepath" : "arrow.triangle.2.circlepath")
                        .foregroundStyle(status.sync?.state == "error" ? Color.red : Color.secondary)
                        .lineLimit(1)
                        .accessibilityIdentifier("sync-status-state")
                    if status.hasAttentionItems {
                        Image(systemName: "exclamationmark.circle")
                            .foregroundStyle(.orange)
                            .accessibilityIdentifier("sync-status-attention-indicator")
                    }
                }
                if let lastSyncLabel = status.lastSyncLabel {
                    Text(lastSyncLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .accessibilityIdentifier("sync-status-last-synced")
                }
            }

            if let error = status.error {
                VStack(alignment: .leading, spacing: 2) {
                    Text(error.message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(3)
                        .accessibilityIdentifier("backend-error-message")
                    if let recovery = error.recovery {
                        Text(recovery)
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .lineLimit(3)
                            .accessibilityIdentifier("backend-error-recovery")
                    }
                }
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
    let isLoading: Bool
    let actionError: PresentedError?
    let markSeen: () async -> Void
    let markReviewed: () async -> Void
    let markInProgress: () async -> Void
    let moveToBacklog: () async -> Void
    let markDone: () async -> Void
    let remove: () async -> Void
    let openInBrowser: () async -> Void

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
                        Task {
                            await openInBrowser()
                        }
                    }
                    .accessibilityIdentifier("task-action-open-browser")
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

            if let actionError {
                VStack(alignment: .leading, spacing: 2) {
                    Text(actionError.message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(3)
                        .accessibilityIdentifier("task-action-error")
                    if let recovery = actionError.recovery {
                        Text(recovery)
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .lineLimit(3)
                            .accessibilityIdentifier("task-action-error-recovery")
                    }
                }
            }

            Spacer()
        }
        .padding(24)
        .frame(minWidth: 340, alignment: .topLeading)
    }
}

private struct CreateManualTaskSheet: View {
    let isLoading: Bool
    let create: (String, String?, [String]?) async -> Bool
    let dismiss: () -> Void

    @State private var title: String = ""
    @State private var project: String = ""
    @State private var tagsInput: String = ""
    @State private var isSubmitting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Manual Task")
                .font(.title3)
                .fontWeight(.semibold)

            Form {
                TextField("Title", text: $title)
                TextField("Project (optional)", text: $project)
                TextField("Tags (comma separated, optional)", text: $tagsInput)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .disabled(isSubmitting)

                Button("Create") {
                    submit()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isSubmitting || isLoading || trimmedTitle.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func submit() {
        let titleValue = trimmedTitle
        guard !titleValue.isEmpty else { return }

        let projectTrimmed = project.trimmingCharacters(in: .whitespacesAndNewlines)
        let projectValue = projectTrimmed.isEmpty ? nil : projectTrimmed

        let parsedTags = tagsInput
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let tagsValue = parsedTags.isEmpty ? nil : parsedTags

        isSubmitting = true
        Task {
            let succeeded = await create(titleValue, projectValue, tagsValue)
            isSubmitting = false
            if succeeded {
                dismiss()
            }
        }
    }
}

private struct SettingsView: View {
    @EnvironmentObject private var backendStatus: BackendStatusModel

    var body: some View {
        Form {
            Section("GitHub CLI") {
                LabeledContent("Status", value: ghStatusLabel)
                    .accessibilityIdentifier("settings-gh-status")
                LabeledContent("Path", value: backendStatus.diagnostics?.gh.path ?? "—")
                    .accessibilityIdentifier("settings-gh-path")
                LabeledContent("Version", value: backendStatus.diagnostics?.gh.version ?? "—")
                    .accessibilityIdentifier("settings-gh-version")
            }
            Section("Authentication") {
                LabeledContent("Authenticated", value: authenticatedLabel)
                    .accessibilityIdentifier("settings-auth-status")
                LabeledContent("Username", value: backendStatus.auth?.username ?? "—")
                    .accessibilityIdentifier("settings-auth-username")
                LabeledContent("Host", value: backendStatus.diagnostics?.host ?? "—")
                    .accessibilityIdentifier("settings-auth-host")
                LabeledContent("GH_CONFIG_DIR", value: backendStatus.auth?.workspaceGhConfigDir ?? "—")
                    .accessibilityIdentifier("settings-gh-config-dir")
            }
            Section("Helper PATH") {
                if let path = backendStatus.diagnostics?.helperPath, !path.isEmpty {
                    ForEach(Array(path.enumerated()), id: \.offset) { _, entry in
                        Text(entry)
                            .font(.system(.caption, design: .monospaced))
                            .accessibilityIdentifier("settings-helper-path-row")
                    }
                } else {
                    Text("—").accessibilityIdentifier("settings-helper-path-empty")
                }
                if backendStatus.diagnostics?.gh.found == false {
                    Text("Relaunch Agendum if you've just installed gh — the helper's PATH is captured at launch and won't pick up new installs until restart.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .accessibilityIdentifier("settings-helper-path-relaunch-hint")
                }
            }
            if let prose = backendStatus.auth?.repairInstructions {
                Section("Repair") {
                    Text(prose)
                        .font(.caption)
                        .accessibilityIdentifier("settings-repair-instructions")
                }
            }
            Section {
                HStack {
                    Button("Refresh") {
                        Task { await backendStatus.refreshDiagnostics() }
                    }
                    .accessibilityIdentifier("settings-action-refresh")
                    Button("Copy gh auth login command") {
                        backendStatus.copyAuthLoginCommand()
                    }
                    .disabled(backendStatus.auth?.repairCommand == nil)
                    .accessibilityIdentifier("settings-action-copy-login")
                    Button("Open install page") {
                        backendStatus.openGHInstallURL()
                    }
                    .accessibilityIdentifier("settings-action-open-install")
                }
                if let err = backendStatus.diagnosticsError {
                    Text(err.message)
                        .foregroundColor(.red)
                        .accessibilityIdentifier("settings-diagnostics-error")
                    if let recovery = err.recovery {
                        Text(recovery)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .accessibilityIdentifier("settings-diagnostics-error-recovery")
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 520)
        .task {
            await backendStatus.refreshDiagnostics()
        }
    }

    private var ghStatusLabel: String {
        guard let gh = backendStatus.diagnostics?.gh else { return "Loading…" }
        return gh.found ? "Installed" : "Not found"
    }

    private var authenticatedLabel: String {
        guard let auth = backendStatus.auth else { return "Loading…" }
        return auth.authenticated ? "Yes" : "No"
    }
}
