import AgendumFeature
import AgendumModel
import SwiftUI
@preconcurrency import UserNotifications

@main
struct AgendumMacApp: App {
    @State private var settingsBackendStatus = BackendStatusModel.live()
    private let commands = TaskDashboardCommands.standard

    var body: some Scene {
        WindowGroup {
            DashboardSceneRoot(commands: commands)
        }
        .commands {
            DashboardMenuCommands(commands: commands)
        }

        Settings {
            SettingsView()
                .environment(settingsBackendStatus)
        }
    }
}

@MainActor
private struct DashboardCommandTarget {
    let backendStatus: BackendStatusModel
    let isShowingCreateManualTask: Binding<Bool>
    let selectedTaskID: Binding<TaskItem.ID?>
}

private struct DashboardCommandTargetKey: FocusedValueKey {
    typealias Value = DashboardCommandTarget
}

private extension FocusedValues {
    var dashboardCommandTarget: DashboardCommandTarget? {
        get { self[DashboardCommandTargetKey.self] }
        set { self[DashboardCommandTargetKey.self] = newValue }
    }
}

private struct DashboardMenuCommands: Commands {
    let commands: TaskDashboardCommands
    @FocusedValue(\.dashboardCommandTarget) private var target

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Task") {
                target?.isShowingCreateManualTask.wrappedValue = true
            }
            .keyboardShortcut("n", modifiers: [.command])
            .disabled(!isAvailable(commands.menuNewTask))
            .accessibilityIdentifier("menu-action-new-task")

            Button("Refresh") {
                perform(commands.menuRefresh, clearsSelection: true)
            }
            .keyboardShortcut("r", modifiers: [.command])
            .disabled(!isAvailable(commands.menuRefresh))
            .accessibilityIdentifier("menu-action-refresh")

            Button("Sync Now") {
                perform(commands.menuSync)
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(!isAvailable(commands.menuSync))
            .accessibilityIdentifier("menu-action-sync")
        }

        CommandMenu("Task") {
            taskMenuButton(
                title: "Open in Browser",
                command: commands.menuOpenInBrowser,
                shortcut: ("l", [.command, .shift]),
                identifier: "menu-action-open-browser"
            )
            Divider()
            taskMenuButton(
                title: "Mark Seen",
                command: commands.menuMarkSeen,
                shortcut: ("m", [.command, .option]),
                identifier: "menu-action-mark-seen"
            )
            taskMenuButton(
                title: "Mark Reviewed",
                command: commands.menuMarkReviewed,
                shortcut: ("r", [.command, .option]),
                identifier: "menu-action-mark-reviewed"
            )
            taskMenuButton(
                title: "Mark In Progress",
                command: commands.menuMarkInProgress,
                shortcut: ("i", [.command, .option]),
                identifier: "menu-action-mark-in-progress"
            )
            taskMenuButton(
                title: "Move to Backlog",
                command: commands.menuMoveToBacklog,
                shortcut: ("b", [.command, .option]),
                identifier: "menu-action-move-to-backlog"
            )
            taskMenuButton(
                title: "Mark Done",
                command: commands.menuMarkDone,
                shortcut: ("d", [.command, .option]),
                identifier: "menu-action-mark-done"
            )
            Divider()
            taskMenuButton(
                title: "Remove",
                command: commands.menuRemove,
                shortcut: (KeyEquivalent.delete, [.command, .shift]),
                identifier: "menu-action-remove"
            )
        }
    }

    @MainActor
    private func isAvailable(_ command: TaskDashboardCommand) -> Bool {
        guard let target else { return false }
        return command.availability(on: target.backendStatus)
    }

    @MainActor
    private func perform(_ command: TaskDashboardCommand, clearsSelection: Bool = false) {
        guard let target else { return }
        if clearsSelection {
            target.selectedTaskID.wrappedValue = nil
        }
        let model = target.backendStatus
        Task {
            await command.perform(on: model)
        }
    }

    @MainActor
    @ViewBuilder
    private func taskMenuButton(
        title: String,
        command: TaskDashboardCommand,
        shortcut: (key: KeyEquivalent, modifiers: EventModifiers),
        identifier: String
    ) -> some View {
        Button(title) {
            perform(command)
        }
        .keyboardShortcut(shortcut.key, modifiers: shortcut.modifiers)
        .disabled(!isAvailable(command))
        .accessibilityIdentifier(identifier)
    }
}

@MainActor
private struct DashboardSceneRoot: View {
    let commands: TaskDashboardCommands
    @State private var backendStatus = BackendStatusModel.live()
    @State private var isShowingCreateManualTask = false
    @State private var didInitialRefresh = false
    @SceneStorage("dashboard.selectedTaskID") private var selectedTaskID: TaskItem.ID?
    @SceneStorage("dashboard.v2.sourceSelection") private var sourceSelectionRaw = TaskSource.default.rawValue
    @SceneStorage("dashboard.columnVisibility") private var columnVisibilityRaw = StoredColumnVisibility.automatic.rawValue
    @SceneStorage("dashboard.filter.source") private var filterSource = ""
    @SceneStorage("dashboard.filter.status") private var filterStatus = ""
    @SceneStorage("dashboard.filter.project") private var filterProject = ""
    @SceneStorage("dashboard.filter.includeSeen") private var filterIncludeSeen = TaskListFilters.default.includeSeen
    @SceneStorage("dashboard.filter.limit") private var filterLimit = TaskListFilters.default.limit
    @SceneStorage("dashboard.didInitializeState") private var didInitializeSceneState = false
    @AppStorage("dashboard.persisted.selectedTaskID") private var persistedSelectedTaskID = -1
    @AppStorage("dashboard.v2.persisted.sourceSelection") private var persistedSourceSelectionRaw = TaskSource.default.rawValue
    @AppStorage("dashboard.persisted.columnVisibility") private var persistedColumnVisibilityRaw = StoredColumnVisibility.automatic.rawValue
    @AppStorage("dashboard.persisted.filter.source") private var persistedFilterSource = ""
    @AppStorage("dashboard.persisted.filter.status") private var persistedFilterStatus = ""
    @AppStorage("dashboard.persisted.filter.project") private var persistedFilterProject = ""
    @AppStorage("dashboard.persisted.filter.includeSeen") private var persistedFilterIncludeSeen = TaskListFilters.default.includeSeen
    @AppStorage("dashboard.persisted.filter.limit") private var persistedFilterLimit = TaskListFilters.default.limit

    var body: some View {
        TaskDashboardView(
            backendStatus: backendStatus,
            commands: commands,
            columnVisibility: columnVisibility,
            selection: sourceSelection,
            filters: sceneFilterBinding,
            isShowingCreateManualTask: $isShowingCreateManualTask,
            selectedTask: $selectedTaskID
        )
        .focusedSceneValue(
            \.dashboardCommandTarget,
            DashboardCommandTarget(
                backendStatus: backendStatus,
                isShowingCreateManualTask: $isShowingCreateManualTask,
                selectedTaskID: $selectedTaskID
            )
        )
        .task {
            guard !didInitialRefresh else { return }
            didInitialRefresh = true
            restoreDefaultWindowStateIfNeeded()
            didInitializeSceneState = true
            backendStatus.restoreSceneState(filters: sceneFilters, selectedTaskID: selectedTaskID)
            await backendStatus.refresh()
            backendStatus.setBadgeForAttentionCount()
        }
        .onChange(of: selectedTaskID) { _, newValue in
            didInitializeSceneState = true
            persistedSelectedTaskID = newValue ?? -1
            backendStatus.setSelectedTaskID(newValue)
        }
        .onChange(of: backendStatus.filters) { _, newValue in
            writeSceneFilters(newValue)
        }
        .onChange(of: backendStatus.hasAttentionItems) { _, _ in
            backendStatus.setBadgeForAttentionCount()
        }
    }

    private var sourceSelection: Binding<TaskSource?> {
        Binding(
            get: { taskSource(from: sourceSelectionRaw) ?? .default },
            set: {
                let rawValue = ($0 ?? .default).rawValue
                didInitializeSceneState = true
                sourceSelectionRaw = rawValue
                persistedSourceSelectionRaw = rawValue
            }
        )
    }

    private var columnVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { StoredColumnVisibility(rawValue: columnVisibilityRaw)?.value ?? .automatic },
            set: {
                let rawValue = StoredColumnVisibility($0).rawValue
                didInitializeSceneState = true
                columnVisibilityRaw = rawValue
                persistedColumnVisibilityRaw = rawValue
            }
        )
    }

    private var sceneFilterBinding: Binding<TaskListFilters> {
        Binding(
            get: { sceneFilters },
            set: { writeSceneFilters($0) }
        )
    }

    private var sceneFilters: TaskListFilters {
        TaskListFilters(
            source: filterSource.nilIfEmpty,
            status: filterStatus.nilIfEmpty,
            project: filterProject.nilIfEmpty,
            includeSeen: filterIncludeSeen,
            limit: TaskListFilters.allowedLimits.contains(filterLimit) ? filterLimit : TaskListFilters.default.limit
        )
    }

    private func writeSceneFilters(_ filters: TaskListFilters) {
        didInitializeSceneState = true
        filterSource = filters.source ?? ""
        filterStatus = filters.status ?? ""
        filterProject = filters.project ?? ""
        filterIncludeSeen = filters.includeSeen
        filterLimit = filters.limit
        persistedFilterSource = filterSource
        persistedFilterStatus = filterStatus
        persistedFilterProject = filterProject
        persistedFilterIncludeSeen = filterIncludeSeen
        persistedFilterLimit = filterLimit
    }

    private func restoreDefaultWindowStateIfNeeded() {
        guard !didInitializeSceneState else { return }

        if selectedTaskID == nil, persistedSelectedTaskID > 0 {
            selectedTaskID = persistedSelectedTaskID
        }
        if taskSource(from: sourceSelectionRaw) == nil || taskSource(from: sourceSelectionRaw) == .default {
            sourceSelectionRaw = (taskSource(from: persistedSourceSelectionRaw) ?? .default).rawValue
        }
        if StoredColumnVisibility(rawValue: columnVisibilityRaw) == nil || columnVisibilityRaw == StoredColumnVisibility.automatic.rawValue {
            columnVisibilityRaw = StoredColumnVisibility(rawValue: persistedColumnVisibilityRaw)?.rawValue ?? StoredColumnVisibility.automatic.rawValue
        }
        if filterSource.isEmpty {
            filterSource = persistedFilterSource
        }
        if filterStatus.isEmpty {
            filterStatus = persistedFilterStatus
        }
        if filterProject.isEmpty {
            filterProject = persistedFilterProject
        }
        if filterIncludeSeen == TaskListFilters.default.includeSeen {
            filterIncludeSeen = persistedFilterIncludeSeen
        }
        if filterLimit == TaskListFilters.default.limit {
            filterLimit = TaskListFilters.allowedLimits.contains(persistedFilterLimit) ? persistedFilterLimit : TaskListFilters.default.limit
        }
    }

    private func taskSource(from rawValue: String) -> TaskSource? {
        switch rawValue {
        case "all":
            .all
        case "pr_authored":
            .authored
        case "pr_review":
            .review
        case "issue":
            .issues
        case "manual":
            .manual
        default:
            TaskSource(rawValue: rawValue)
        }
    }
}

private enum StoredColumnVisibility: String {
    case automatic
    case all
    case doubleColumn
    case detailOnly

    init(_ visibility: NavigationSplitViewVisibility) {
        switch visibility {
        case .automatic:
            self = .automatic
        case .all:
            self = .all
        case .doubleColumn:
            self = .doubleColumn
        case .detailOnly:
            self = .detailOnly
        default:
            self = .automatic
        }
    }

    var value: NavigationSplitViewVisibility {
        switch self {
        case .automatic:
            .automatic
        case .all:
            .all
        case .doubleColumn:
            .doubleColumn
        case .detailOnly:
            .detailOnly
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private extension TaskSource {
    var systemImage: String {
        switch self {
        case .all:
            "tray.2"
        case .authored:
            "arrow.triangle.pull"
        case .review:
            "person.crop.circle.badge.checkmark"
        case .issues:
            "tray.full"
        case .manual:
            "checklist"
        }
    }

    func matches(_ task: TaskItem) -> Bool {
        switch self {
        case .all:
            true
        case .authored:
            task.source == .authored
        case .review:
            task.source == .review
        case .issues:
            task.source == .issues
        case .manual:
            task.source == .manual
        }
    }

    var sectionTitle: String {
        switch self {
        case .all:
            "ALL"
        case .authored:
            "MY PULL REQUESTS"
        case .review:
            "REVIEWS REQUESTED"
        case .issues:
            "ISSUES"
        case .manual:
            "MANUAL"
        }
    }

    var sectionColor: Color {
        switch self {
        case .all:
            Palette.sectionIssuesManual
        case .authored:
            Palette.sectionAuthored
        case .review:
            Palette.sectionReview
        case .issues, .manual:
            Palette.sectionIssuesManual
        }
    }
}

private enum Palette {
    static let sectionAuthored = Color(hex: "#ffaa00")
    static let sectionReview = Color(hex: "#a78bfa")
    static let sectionIssuesManual = Color(hex: "#60a5fa")

    static func status(_ value: String) -> Color {
        switch value {
        case "open":
            Color(hex: "#60a5fa")
        case "awaiting review":
            Color(hex: "#ffaa00")
        case "changes requested":
            Color(hex: "#f87171")
        case "review received":
            Color(hex: "#f59e0b")
        case "approved":
            Color(hex: "#4ade80")
        case "review requested":
            Color(hex: "#a78bfa")
        case "reviewed":
            Color(hex: "#7c6aad")
        case "re-review requested":
            Color(hex: "#e879f9")
        case "backlog":
            Color(hex: "#c7a17a")
        case "in progress":
            Color(hex: "#2dd4bf")
        case "draft", "merged", "closed", "done":
            Color(hex: "#888888")
        default:
            Color(hex: "#888888")
        }
    }
}

private extension Color {
    init(hex: String) {
        let trimmed = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let value = Int(trimmed, radix: 16) ?? 0x888888
        let red = Double((value >> 16) & 0xff) / 255
        let green = Double((value >> 8) & 0xff) / 255
        let blue = Double(value & 0xff) / 255
        self.init(red: red, green: green, blue: blue)
    }
}

private struct TaskDashboardView: View {
    var backendStatus: BackendStatusModel
    let commands: TaskDashboardCommands
    @Binding var columnVisibility: NavigationSplitViewVisibility
    @Binding var selection: TaskSource?
    @Binding var filters: TaskListFilters
    @Binding var isShowingCreateManualTask: Bool
    @Binding var selectedTask: TaskItem.ID?
    @State private var actionTaskID: TaskItem.ID?

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(TaskSource.allCases, selection: $selection) { source in
                Label(source.rawValue, systemImage: source.systemImage)
                    .badge(backendStatus.tasks.filter(source.matches).count)
                    .tag(source)
            }
            .navigationTitle("Agendum")
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 0) {
                    TaskListFiltersPanel(status: backendStatus, filters: $filters)
                    BackendStatusPanel(status: backendStatus) {
                        selectedTask = nil
                    }
                }
            }
        } detail: {
            List(selection: $selectedTask) {
                ForEach(sections) { section in
                    Section {
                        ForEach(section.tasks) { task in
                            TaskRow(task: task)
                                .tag(task.id)
                                .contentShape(Rectangle())
                                .simultaneousGesture(
                                    TapGesture(count: 2).onEnded {
                                        presentActions(for: task.id)
                                    }
                                )
                        }
                    } header: {
                        TaskSectionHeader(section: section)
                    }
                }
            }
            .navigationTitle(selectedSource.rawValue)
            .controlSize(.small)
            .onKeyPress(.return) {
                presentSelectedTaskActions()
                return .handled
            }
            .onKeyPress(.space) {
                presentSelectedTaskActions()
                return .handled
            }
            .onChange(of: visibleTaskIDs) { _, _ in
                revalidateSelectionForVisibleTasks()
            }
            .onChange(of: backendStatus.tasks) { _, _ in
                revalidateSelectionForVisibleTasks()
            }
            .onChange(of: selectedSource) { _, _ in
                revalidateSelectionForVisibleTasks()
            }
            .onChange(of: filters) { _, _ in
                revalidateSelectionForVisibleTasks()
            }
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
            .sheet(isPresented: actionSheetBinding) {
                if let task = actionTaskID.flatMap(visibleTask) {
                    TaskActionModal(
                        task: task,
                        isLoading: backendStatus.isLoading,
                        actionError: backendStatus.errorForTask(id: task.id),
                        perform: { action in
                            await perform(action, on: task)
                        },
                        dismiss: {
                            actionTaskID = nil
                        }
                    )
                }
            }
        }
    }

    private var selectedSource: TaskSource {
        selection ?? .all
    }

    private var filteredTasks: [TaskItem] {
        backendStatus.tasks.filter(selectedSource.matches)
    }

    private var sections: [TaskDisplaySection] {
        TaskDisplaySection.sections(for: filteredTasks, selection: selectedSource)
    }

    private var visibleTaskIDs: [TaskItem.ID] {
        sections.flatMap { $0.tasks.map(\.id) }
    }

    private var actionSheetBinding: Binding<Bool> {
        Binding(
            get: { actionTaskID.flatMap(visibleTask) != nil },
            set: { isPresented in
                if !isPresented {
                    actionTaskID = nil
                }
            }
        )
    }

    private func presentSelectedTaskActions() {
        guard
            let selectedTask,
            TaskDisplaySection.containsTask(withID: selectedTask, in: sections)
        else {
            revalidateSelectionForVisibleTasks()
            return
        }
        presentActions(for: selectedTask)
    }

    private func presentActions(for id: TaskItem.ID) {
        guard TaskDisplaySection.containsTask(withID: id, in: sections) else {
            revalidateSelectionForVisibleTasks()
            return
        }
        selectedTask = id
        backendStatus.setSelectedTaskID(id)
        actionTaskID = id
    }

    private func visibleTask(_ id: TaskItem.ID) -> TaskItem? {
        TaskDisplaySection.task(withID: id, in: sections)
    }

    private func revalidateSelectionForVisibleTasks() {
        if let selectedTask, !TaskDisplaySection.containsTask(withID: selectedTask, in: sections) {
            self.selectedTask = nil
            backendStatus.setSelectedTaskID(nil)
        }

        if let actionTaskID, !TaskDisplaySection.containsTask(withID: actionTaskID, in: sections) {
            self.actionTaskID = nil
        }
    }

    private func perform(_ action: TaskDetailAction, on task: TaskItem) async {
        selectedTask = task.id
        backendStatus.setSelectedTaskID(task.id)

        switch action {
        case .openBrowser:
            await backendStatus.openTaskURL(id: task.id)
        case .markSeen:
            await backendStatus.markSeen(id: task.id)
        case .markReviewed:
            await backendStatus.markReviewed(id: task.id)
        case .markInProgress:
            await backendStatus.markInProgress(id: task.id)
        case .moveToBacklog:
            await backendStatus.moveToBacklog(id: task.id)
        case .markDone:
            await backendStatus.markDone(id: task.id)
        case .remove:
            await backendStatus.removeTask(id: task.id)
        }

        guard backendStatus.errorForTask(id: task.id) == nil else { return }
        if action == .markReviewed || action == .markDone || action == .remove {
            selectedTask = nil
        }
        actionTaskID = nil
    }
}

private struct TaskListFiltersPanel: View {
    var status: BackendStatusModel
    @Binding var filters: TaskListFilters
    @AppStorage("task-list-filters-expanded") private var isExpanded: Bool = true

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
                    get: { filters.status ?? "" },
                    set: { newValue in
                        var next = filters
                        next.status = newValue.isEmpty ? nil : newValue
                        apply(next)
                    }
                )) {
                    Text("All").tag("")
                    ForEach(Self.statusOptions, id: \.self) { value in
                        Text(value).tag(value)
                    }
                }
                .accessibilityIdentifier("task-list-filter-status")

                Picker("Source", selection: Binding(
                    get: { filters.source ?? "" },
                    set: { newValue in
                        var next = filters
                        next.source = newValue.isEmpty ? nil : newValue
                        apply(next)
                    }
                )) {
                    Text("All").tag("")
                    ForEach(Self.sourceOptions, id: \.self) { value in
                        Text(value).tag(value)
                    }
                }
                .accessibilityIdentifier("task-list-filter-source")

                TextField("Project", text: Binding(
                    get: { filters.project ?? "" },
                    set: { newValue in
                        var next = filters
                        next.project = newValue.isEmpty ? nil : newValue
                        filters = next
                    }
                ), prompt: Text("Exact match"))
                    .onSubmit {
                        Task { await status.applyFilters(filters) }
                    }
                    .accessibilityIdentifier("task-list-filter-project")

                Toggle("Include seen items", isOn: Binding(
                    get: { filters.includeSeen },
                    set: { newValue in
                        var next = filters
                        next.includeSeen = newValue
                        apply(next)
                    }
                ))
                    .accessibilityIdentifier("task-list-filter-include-seen")

                Picker("Limit", selection: Binding(
                    get: { filters.limit },
                    set: { newValue in
                        var next = filters
                        next.limit = newValue
                        apply(next)
                    }
                )) {
                    ForEach(TaskListFilters.allowedLimits, id: \.self) { value in
                        Text("\(value)").tag(value)
                    }
                }
                .accessibilityIdentifier("task-list-filter-limit")

                Button("Clear filters") {
                    apply(.default)
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
    }

    private func apply(_ next: TaskListFilters) {
        filters = next
        Task {
            await status.applyFilters(next)
        }
    }
}

private struct BackendStatusPanel: View {
    var status: BackendStatusModel
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
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle()
                .fill(task.isUnseen ? Palette.status("changes requested") : Color.clear)
                .frame(width: 7, height: 7)
                .accessibilityLabel(task.isUnseen ? "Unread" : "Read")

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(task.title)
                        .lineLimit(1)

                    Spacer(minLength: 12)

                    Text(linkLabel)
                        .font(.caption)
                        .foregroundStyle(linkColor)
                        .monospacedDigit()
                        .lineLimit(1)
                }

                HStack(spacing: 8) {
                    Text(task.status)
                        .foregroundStyle(Palette.status(task.status))
                        .lineLimit(1)

                    if let author = task.author, !author.isEmpty {
                        Text(author)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Text(task.project)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                .font(.caption)
            }
        }
        .padding(.vertical, 2)
    }

    private var linkLabel: String {
        guard let number = task.number else {
            return task.source == .manual ? "Manual" : "No number"
        }
        return task.backendSource.hasPrefix("pr") ? "PR #\(number)" : "Issue #\(number)"
    }

    private var linkColor: Color {
        task.number == nil ? Color.secondary.opacity(0.65) : Palette.sectionIssuesManual
    }
}

private struct TaskSectionHeader: View {
    let section: TaskDisplaySection

    var body: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(section.source.sectionColor)
                .frame(width: 3, height: 13)
            Text(section.source.sectionTitle)
                .foregroundStyle(section.source.sectionColor)
                .font(.caption)
                .fontWeight(.semibold)
            Text("\(section.tasks.count)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Spacer()
        }
        .textCase(nil)
        .padding(.top, 6)
    }
}

private struct TaskActionModal: View {
    let task: TaskItem
    let isLoading: Bool
    let actionError: PresentedError?
    let perform: (TaskDetailAction) async -> Void
    let dismiss: () -> Void

    @State private var runningAction: TaskDetailAction?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(task.title)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Text(task.status)
                        .foregroundStyle(Palette.status(task.status))
                    if let author = task.author, !author.isEmpty {
                        Text(author)
                            .foregroundStyle(.secondary)
                    }
                    Text(task.project)
                        .foregroundStyle(.tertiary)
                    Text(linkLabel)
                        .foregroundStyle(linkColor)
                }
                .font(.caption)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(availableActions, id: \.self) { action in
                    Button(role: action == .remove ? .destructive : nil) {
                        run(action)
                    } label: {
                        HStack {
                            Label(action.title, systemImage: action.systemImage)
                            Spacer()
                            if runningAction == action {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                    }
                    .disabled(isLoading || runningAction != nil)
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("task-action-\(action.rawValue)")
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
                            .foregroundStyle(.tertiary)
                            .lineLimit(3)
                            .accessibilityIdentifier("task-action-error-recovery")
                    }
                }
            }

            HStack {
                Spacer()
                Button("Close", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .disabled(runningAction != nil)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private var availableActions: [TaskDetailAction] {
        let preferredOrder: [TaskDetailAction] = [
            .openBrowser,
            .markSeen,
            .markReviewed,
            .markInProgress,
            .moveToBacklog,
            .markDone,
            .remove,
        ]
        return preferredOrder.filter(task.availableDetailActions.contains)
    }

    private var linkLabel: String {
        guard let number = task.number else {
            return task.source == .manual ? "Manual" : "No number"
        }
        return task.backendSource.hasPrefix("pr") ? "PR #\(number)" : "Issue #\(number)"
    }

    private var linkColor: Color {
        task.number == nil ? Color.secondary.opacity(0.65) : Palette.sectionIssuesManual
    }

    private func run(_ action: TaskDetailAction) {
        runningAction = action
        Task {
            await perform(action)
            runningAction = nil
        }
    }
}

private extension TaskDetailAction {
    var title: String {
        switch self {
        case .openBrowser:
            "Open in Browser"
        case .markSeen:
            "Mark Seen"
        case .markReviewed:
            "Mark Reviewed"
        case .markInProgress:
            "Mark In Progress"
        case .moveToBacklog:
            "Move to Backlog"
        case .markDone:
            "Mark Done"
        case .remove:
            "Remove"
        }
    }

    var systemImage: String {
        switch self {
        case .openBrowser:
            "safari"
        case .markSeen:
            "circle"
        case .markReviewed:
            "checkmark.bubble"
        case .markInProgress:
            "play.circle"
        case .moveToBacklog:
            "tray"
        case .markDone:
            "checkmark.circle"
        case .remove:
            "trash"
        }
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
    @Environment(BackendStatusModel.self) private var backendStatus
    @State private var notificationAuthorizationStatus: UNAuthorizationStatus?

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
            Section("Notifications") {
                LabeledContent("Status", value: notificationStatusLabel)
                    .accessibilityIdentifier("settings-notifications-status")
                if notificationAuthorizationStatus == .notDetermined {
                    Button("Enable notifications") {
                        Task {
                            do {
                                let granted = try await UNUserNotificationCenter.current()
                                    .requestAuthorization(options: [.alert, .badge, .sound])
                                logger.notice("Notification authorization request granted=\(granted, privacy: .public)")
                            } catch {
                                logger.error("Notification authorization request failed: \(error.localizedDescription, privacy: .public)")
                            }
                            await refreshNotificationSettings()
                        }
                    }
                    .accessibilityIdentifier("settings-action-enable-notifications")
                } else if notificationAuthorizationStatus == .denied {
                    Text("Open System Settings → Notifications → Agendum to enable notifications.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .accessibilityIdentifier("settings-notifications-denied-hint")
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
            await backendStatus.refresh()
            await backendStatus.refreshDiagnostics()
            await refreshNotificationSettings()
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

    private var notificationStatusLabel: String {
        switch notificationAuthorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return "Allowed"
        case .denied:
            return "Denied"
        case .notDetermined:
            return "Not requested"
        case .none:
            return "Loading…"
        @unknown default:
            return "Unknown"
        }
    }

    private func refreshNotificationSettings() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationAuthorizationStatus = settings.authorizationStatus
    }
}
