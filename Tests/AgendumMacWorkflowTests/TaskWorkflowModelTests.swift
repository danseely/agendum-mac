@testable import AgendumMacWorkflow
import AgendumMacCore
import XCTest

@MainActor
final class TaskWorkflowModelTests: XCTestCase {
    func testRefreshLoadsWorkspaceAuthSyncAndTasks() async throws {
        let backend = FakeBackend()
        await backend.setTasks([task(id: 17, title: "Review release workflow", source: "pr_review", seen: false)])
        let model = BackendStatusModel(client: backend, sleep: immediateSleep)

        await model.refresh()

        XCTAssertEqual(model.workspace?.id, "base")
        XCTAssertEqual(model.workspaces.map(\.id), ["base", "example-org"])
        XCTAssertEqual(model.auth?.username, "dan")
        XCTAssertEqual(model.sync?.state, "idle")
        XCTAssertEqual(model.tasks.map(\.id), [17])
        XCTAssertEqual(model.tasks[0].source, .review)
        XCTAssertNil(model.errorMessage)
        XCTAssertFalse(model.isLoading)
        let calls = await backend.calls
        XCTAssertEqual(calls, ["currentWorkspace", "listWorkspaces", "authStatus", "syncStatus", "listTasks"])
    }

    func testRefreshFailureClearsTasksAndSurfacesError() async throws {
        let backend = FakeBackend()
        await backend.setTasks([task(id: 17)])
        let model = BackendStatusModel(client: backend, sleep: immediateSleep)

        await model.refresh()
        XCTAssertEqual(model.tasks.map(\.id), [17])

        await backend.resetCalls()
        await backend.failNext("currentWorkspace", message: "workspace failed")

        await model.refresh()

        XCTAssertTrue(model.tasks.isEmpty)
        XCTAssertEqual(model.errorMessage, "workspace failed")
        XCTAssertFalse(model.isLoading)
    }

    func testSelectWorkspaceNoOpsForCurrentWorkspaceAndLoadsSelectedWorkspace() async throws {
        let backend = FakeBackend()
        await backend.setTasks([task(id: 17)])
        let model = BackendStatusModel(client: backend, sleep: immediateSleep)
        await model.refresh()
        await backend.resetCalls()

        await model.selectWorkspace(id: "base")

        let noOpCalls = await backend.calls
        XCTAssertEqual(noOpCalls, [])

        await backend.setTasks([task(id: 22, title: "Org task", source: "manual")])
        await model.selectWorkspace(id: "example-org")

        XCTAssertEqual(model.workspace?.id, "example-org")
        XCTAssertEqual(model.auth?.workspaceGhConfigDir, "/tmp/agendum/workspaces/example-org/gh")
        XCTAssertEqual(model.sync?.state, "idle")
        XCTAssertEqual(model.tasks.map(\.id), [22])
        XCTAssertNil(model.errorMessage)
        let calls = await backend.calls
        XCTAssertEqual(calls, ["selectWorkspace:example-org", "listWorkspaces", "listTasks"])
    }

    func testSelectWorkspaceFailureClearsTasksAndSurfacesError() async throws {
        let backend = FakeBackend()
        await backend.setTasks([task(id: 17)])
        let model = BackendStatusModel(client: backend, sleep: immediateSleep)
        await model.refresh()
        await backend.resetCalls()
        await backend.failNext("selectWorkspace", message: "select failed")

        await model.selectWorkspace(id: "example-org")

        XCTAssertTrue(model.tasks.isEmpty)
        XCTAssertEqual(model.errorMessage, "select failed")
        let calls = await backend.calls
        XCTAssertEqual(calls, ["selectWorkspace:example-org"])
    }

    func testForceSyncPollsUntilTerminalStateAndReloadsTasks() async throws {
        let backend = FakeBackend()
        await backend.setForceSyncStatus(sync(state: "running"))
        await backend.setSyncStatusQueue([sync(state: "running"), sync(state: "idle", changes: 3)])
        await backend.setTasks([task(id: 31, title: "Synced task")])
        let sleepRecorder = SleepRecorder()
        let model = BackendStatusModel(
            client: backend,
            syncPollIntervalNanoseconds: 10,
            maxSyncPollAttempts: 5,
            sleep: { nanoseconds in await sleepRecorder.record(nanoseconds) }
        )

        await model.forceSync()

        XCTAssertEqual(model.sync, sync(state: "idle", changes: 3))
        XCTAssertEqual(model.tasks.map(\.id), [31])
        XCTAssertNil(model.errorMessage)
        let sleeps = await sleepRecorder.values
        let calls = await backend.calls
        XCTAssertEqual(sleeps, [10, 10])
        XCTAssertEqual(calls, ["forceSync", "syncStatus", "syncStatus", "listTasks"])
    }

    func testForceSyncPollingFailureKeepsTasksAndSurfacesError() async throws {
        let backend = FakeBackend()
        await backend.setTasks([task(id: 17, title: "Existing")])
        let model = BackendStatusModel(client: backend, sleep: immediateSleep)
        await model.refresh()
        await backend.resetCalls()
        await backend.setForceSyncStatus(sync(state: "running"))
        await backend.failNext("syncStatus", message: "poll failed")

        await model.forceSync()

        XCTAssertEqual(model.tasks.map(\.id), [17])
        XCTAssertEqual(model.sync?.state, "running")
        XCTAssertEqual(model.errorMessage, "poll failed")
        let calls = await backend.calls
        XCTAssertEqual(calls, ["forceSync", "syncStatus"])
    }

    func testDashboardCommandsShareSyncPath() async throws {
        let commands = TaskDashboardCommands.standard
        XCTAssertEqual(commands.menuSync, .sync)
        XCTAssertEqual(commands.toolbarSync, .sync)

        let backend = FakeBackend()
        await backend.setForceSyncStatus(sync(state: "idle", changes: 1))
        await backend.setTasks([task(id: 42)])
        let model = BackendStatusModel(client: backend, sleep: immediateSleep)

        await commands.menuSync.perform(on: model)
        await commands.toolbarSync.perform(on: model)

        XCTAssertEqual(model.sync, sync(state: "idle", changes: 1))
        let calls = await backend.calls
        XCTAssertEqual(calls, ["forceSync", "listTasks", "forceSync", "listTasks"])
    }

    func testDashboardRefreshCommandUsesRefreshPath() async throws {
        let backend = FakeBackend()
        await backend.setTasks([task(id: 17)])
        let model = BackendStatusModel(client: backend, sleep: immediateSleep)

        await TaskDashboardCommands.standard.toolbarRefresh.perform(on: model)

        XCTAssertEqual(model.tasks.map(\.id), [17])
        let calls = await backend.calls
        XCTAssertEqual(calls, ["currentWorkspace", "listWorkspaces", "authStatus", "syncStatus", "listTasks"])
    }

    func testTaskActionsCallBackendAndReloadTasks() async throws {
        let cases: [(String, (BackendStatusModel) async -> Void)] = [
            ("markTaskSeen:17", { await $0.markSeen(id: 17) }),
            ("markTaskReviewed:17", { await $0.markReviewed(id: 17) }),
            ("markTaskInProgress:17", { await $0.markInProgress(id: 17) }),
            ("moveTaskToBacklog:17", { await $0.moveToBacklog(id: 17) }),
            ("markTaskDone:17", { await $0.markDone(id: 17) }),
            ("removeTask:17", { await $0.removeTask(id: 17) }),
        ]

        for (expectedCall, action) in cases {
            let backend = FakeBackend()
            await backend.setTasks([task(id: 99, title: "Reloaded")])
            let model = BackendStatusModel(client: backend, sleep: immediateSleep)

            await action(model)

            XCTAssertEqual(model.tasks.map(\.id), [99], expectedCall)
            let calls = await backend.calls
            XCTAssertEqual(calls, [expectedCall, "listTasks"], expectedCall)
            XCTAssertNil(model.errorMessage, expectedCall)
            XCTAssertTrue(model.taskActionErrors.isEmpty, expectedCall)
        }
    }

    func testTaskActionFailureScopesErrorToTaskAndKeepsGlobalErrorClean() async throws {
        let backend = FakeBackend()
        await backend.setTasks([task(id: 17, title: "Existing")])
        let model = BackendStatusModel(client: backend, sleep: immediateSleep)
        await model.refresh()
        await backend.resetCalls()
        await backend.failNext("markTaskDone", message: "done failed")

        await model.markDone(id: 17)

        XCTAssertEqual(model.tasks.map(\.id), [17])
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.errorForTask(id: 17)?.message, "done failed")
        let calls = await backend.calls
        XCTAssertEqual(calls, ["markTaskDone:17"])
    }

    func testTaskActionSuccessClearsExistingPerTaskError() async throws {
        let backend = FakeBackend()
        await backend.setTasks([task(id: 17, title: "Existing")])
        let model = BackendStatusModel(client: backend, sleep: immediateSleep)
        await model.refresh()
        await backend.failNext("markTaskDone", message: "done failed")
        await model.markDone(id: 17)
        XCTAssertEqual(model.errorForTask(id: 17)?.message, "done failed")

        await model.markInProgress(id: 17)

        XCTAssertNil(model.errorForTask(id: 17))
        XCTAssertTrue(model.taskActionErrors.isEmpty)
    }

    func testTaskActionFailureOnOneTaskDoesNotClearAnotherTasksError() async throws {
        let backend = FakeBackend()
        await backend.setTasks([task(id: 17, title: "First"), task(id: 23, title: "Second")])
        let model = BackendStatusModel(client: backend, sleep: immediateSleep)
        await model.refresh()
        await backend.failNext("markTaskDone", message: "done 17 failed")
        await model.markDone(id: 17)
        XCTAssertEqual(model.errorForTask(id: 17)?.message, "done 17 failed")

        await backend.failNext("markTaskDone", message: "done 23 failed")
        await model.markDone(id: 23)

        XCTAssertEqual(model.errorForTask(id: 17)?.message, "done 17 failed")
        XCTAssertEqual(model.errorForTask(id: 23)?.message, "done 23 failed")
    }

    func testRefreshClearsTaskActionErrors() async throws {
        let backend = FakeBackend()
        await backend.setTasks([task(id: 17, title: "Existing")])
        let model = BackendStatusModel(client: backend, sleep: immediateSleep)
        await model.refresh()
        await backend.failNext("markTaskDone", message: "done failed")
        await model.markDone(id: 17)
        XCTAssertEqual(model.errorForTask(id: 17)?.message, "done failed")

        await model.refresh()

        XCTAssertNil(model.errorForTask(id: 17))
        XCTAssertTrue(model.taskActionErrors.isEmpty)
    }

    func testSelectWorkspaceClearsTaskActionErrors() async throws {
        let backend = FakeBackend()
        await backend.setTasks([task(id: 17, title: "Existing")])
        let model = BackendStatusModel(client: backend, sleep: immediateSleep)
        await model.refresh()
        await backend.failNext("markTaskDone", message: "done failed")
        await model.markDone(id: 17)
        XCTAssertEqual(model.errorForTask(id: 17)?.message, "done failed")

        await backend.setTasks([task(id: 22, title: "Org task", source: "manual")])
        await model.selectWorkspace(id: "example-org")

        XCTAssertNil(model.errorForTask(id: 17))
        XCTAssertTrue(model.taskActionErrors.isEmpty)
    }

    func testCreateManualTaskSucceedsAndReloadsTasks() async throws {
        let backend = FakeBackend()
        await backend.setTasks([task(id: 99, title: "Created via fake", source: "manual")])
        let model = BackendStatusModel(client: backend, sleep: immediateSleep)

        let succeeded = await model.createManualTask(
            title: "Sketch backend contract",
            project: "agendum-mac",
            tags: ["planning", "design"]
        )

        XCTAssertTrue(succeeded)
        XCTAssertEqual(model.tasks.map(\.id), [99])
        XCTAssertNil(model.errorMessage)
        XCTAssertFalse(model.isLoading)
        let calls = await backend.calls
        XCTAssertEqual(
            calls,
            [
                "createManualTask:Sketch backend contract|agendum-mac|[planning,design]",
                "listTasks",
            ]
        )
    }

    func testCreateManualTaskFailureKeepsExistingTasksAndSurfacesError() async throws {
        let backend = FakeBackend()
        await backend.setTasks([task(id: 17, title: "Existing")])
        let model = BackendStatusModel(client: backend, sleep: immediateSleep)
        await model.refresh()
        await backend.resetCalls()
        await backend.failNext("createManualTask", message: "create failed")

        let succeeded = await model.createManualTask(title: "New", project: nil, tags: nil)

        XCTAssertFalse(succeeded)
        XCTAssertEqual(model.tasks.map(\.id), [17])
        XCTAssertEqual(model.errorMessage, "create failed")
        let calls = await backend.calls
        XCTAssertEqual(calls, ["createManualTask:New|nil|nil"])
    }

    func testPresentedErrorExtractsHelperPayloadFields() {
        let payload = BackendErrorPayload(
            code: "auth.required",
            message: "GitHub auth needed",
            detail: "scopes: repo",
            recovery: "Run gh auth login"
        )
        let presented = PresentedError.from(BackendClientError.helperError(payload))
        XCTAssertEqual(presented.message, "GitHub auth needed")
        XCTAssertEqual(presented.recovery, "Run gh auth login")
        XCTAssertEqual(presented.code, "auth.required")
    }

    func testPresentedErrorFallsBackToDescriptionForGenericErrors() {
        let presented = PresentedError.from(TestError(description: "boom"))
        XCTAssertEqual(presented.message, "boom")
        XCTAssertNil(presented.recovery)
        XCTAssertEqual(presented.code, "client.unknown")
    }

    func testPresentedErrorMapsInvalidResponseToProtocolMismatch() {
        let presented = PresentedError.from(BackendClientError.invalidResponse("malformed JSON"))
        XCTAssertEqual(presented.code, "client.protocolMismatch")
        XCTAssertEqual(presented.message, "malformed JSON")
        if let recovery = presented.recovery {
            XCTAssertFalse(recovery.isEmpty)
        } else {
            XCTFail("expected non-nil recovery for .invalidResponse")
        }
    }

    func testPresentedErrorMapsHelperTerminatedToTerminatedCode() {
        let presented = PresentedError.from(BackendClientError.helperTerminated("boom"))
        XCTAssertEqual(presented.code, "client.helperTerminated")
        XCTAssertTrue(presented.message.contains("boom"))
        XCTAssertNotNil(presented.recovery)
    }

    func testPresentedErrorMapsHelperTerminatedEmptyStderrToTerminatedCode() {
        let presented = PresentedError.from(BackendClientError.helperTerminated(""))
        XCTAssertEqual(presented.code, "client.helperTerminated")
        XCTAssertFalse(presented.message.isEmpty)
        XCTAssertNotNil(presented.recovery)
    }

    func testPresentedErrorMapsRequestTimedOutToTimeoutCode() {
        let presented = PresentedError.from(BackendClientError.requestTimedOut(5))
        XCTAssertEqual(presented.code, "client.timeout")
        XCTAssertTrue(presented.message.contains("5"))
        XCTAssertNotNil(presented.recovery)
    }

    func testPresentedErrorMapsUnexpectedResponseIDToProtocolMismatch() {
        let presented = PresentedError.from(BackendClientError.unexpectedResponseID(expected: "a", actual: "b"))
        XCTAssertEqual(presented.code, "client.protocolMismatch")
        XCTAssertTrue(presented.message.contains("b"))
        XCTAssertNotNil(presented.recovery)
    }

    func testPresentedErrorMapsUnsupportedProtocolVersionToVersionCode() {
        let presented = PresentedError.from(BackendClientError.unsupportedProtocolVersion(2))
        XCTAssertEqual(presented.code, "client.unsupportedProtocolVersion")
        XCTAssertTrue(presented.message.contains("2"))
        XCTAssertNotNil(presented.recovery)
    }

    func testPresentedErrorMapsUnknownErrorToClientUnknown() {
        struct DummyError: Error {}
        let presented = PresentedError.from(DummyError())
        XCTAssertEqual(presented.code, "client.unknown")
        XCTAssertNil(presented.recovery)
        XCTAssertEqual(presented.message, String(describing: DummyError()))
    }

    func testPresentedErrorPreservesHelperPayloadCodeAndRecovery() {
        let payload = BackendErrorPayload(
            code: "task.locked",
            message: "Task locked",
            detail: nil,
            recovery: "Refresh and retry"
        )
        let presented = PresentedError.from(BackendClientError.helperError(payload))
        XCTAssertEqual(presented.code, "task.locked")
        XCTAssertEqual(presented.recovery, "Refresh and retry")
        XCTAssertNotEqual(presented.code, "client.helperError")
    }

    func testRefreshFailureSurfacesTimeoutRecoveryToConsumer() async throws {
        let backend = FakeBackend()
        await backend.setTasks([task(id: 1)])
        await backend.failNextWithError("currentWorkspace", error: BackendClientError.requestTimedOut(0.1))
        let model = BackendStatusModel(client: backend, sleep: immediateSleep)

        await model.refresh()

        XCTAssertEqual(model.error?.code, "client.timeout")
        XCTAssertNotNil(model.error?.recovery)
    }

    func testRefreshFailureSurfacesStructuredRecoveryHint() async throws {
        let payload = BackendErrorPayload(
            code: "workspace.invalid",
            message: "Workspace missing",
            detail: nil,
            recovery: "Pick another workspace"
        )
        let backend = FakeBackend()
        await backend.setTasks([task(id: 1)])
        await backend.failNextWithError("currentWorkspace", error: BackendClientError.helperError(payload))
        let model = BackendStatusModel(client: backend, sleep: immediateSleep)

        await model.refresh()

        XCTAssertEqual(model.error?.message, "Workspace missing")
        XCTAssertEqual(model.error?.recovery, "Pick another workspace")
        XCTAssertEqual(model.error?.code, "workspace.invalid")
        XCTAssertEqual(model.errorMessage, "Workspace missing")
    }

    func testTaskActionFailureSurfacesStructuredRecoveryHint() async throws {
        let payload = BackendErrorPayload(
            code: "task.locked",
            message: "Task locked",
            detail: nil,
            recovery: "Refresh and retry"
        )
        let backend = FakeBackend()
        await backend.setTasks([task(id: 17, title: "Existing")])
        let model = BackendStatusModel(client: backend, sleep: immediateSleep)
        await model.refresh()
        await backend.failNextWithError("markTaskDone", error: BackendClientError.helperError(payload))

        await model.markDone(id: 17)

        let perTask = model.errorForTask(id: 17)
        XCTAssertEqual(perTask?.message, "Task locked")
        XCTAssertEqual(perTask?.recovery, "Refresh and retry")
        XCTAssertEqual(perTask?.code, "task.locked")
        XCTAssertNil(model.error)
    }

    func testLastSyncLabelFormatsIso8601Timestamp() async throws {
        let backend = FakeBackend()
        await backend.setTasks([])
        await backend.setSyncStatusOverride(
            sync(state: "idle", lastSyncAt: "2026-05-02T12:30:00Z")
        )
        let fixedNow = ISO8601DateFormatter().date(from: "2026-05-02T12:35:00Z") ?? Date()
        let model = BackendStatusModel(
            client: backend,
            sleep: immediateSleep,
            now: { fixedNow },
            locale: Locale(identifier: "en_US_POSIX")
        )

        await model.refresh()

        let label = model.lastSyncLabel
        XCTAssertNotNil(label)
        XCTAssertTrue(label?.hasPrefix("Last synced ") ?? false, "expected prefix, got \(label ?? "nil")")
        XCTAssertTrue(label?.contains("min") ?? false, "expected 'min' in \(label ?? "nil")")
        XCTAssertTrue(label?.contains("ago") ?? false, "expected 'ago' in \(label ?? "nil")")
    }

    func testLastSyncLabelNilWhenNoTimestamp() async throws {
        let backend = FakeBackend()
        await backend.setTasks([])
        let model = BackendStatusModel(
            client: backend,
            sleep: immediateSleep,
            locale: Locale(identifier: "en_US_POSIX")
        )

        await model.refresh()

        XCTAssertNil(model.lastSyncLabel)
    }

    func testHasAttentionItemsReflectsSyncStatus() async throws {
        let backend = FakeBackend()
        await backend.setTasks([])
        await backend.setSyncStatusOverride(
            sync(state: "idle", hasAttentionItems: true)
        )
        let model = BackendStatusModel(client: backend, sleep: immediateSleep)

        await model.refresh()

        XCTAssertTrue(model.hasAttentionItems)
    }

    func testDetailActionAvailability() {
        let review = TaskItem(task: task(id: 1, source: "pr_review", url: "https://github.com/danseely/agendum-mac/pull/1", seen: false))
        XCTAssertEqual(review.availableDetailActions, [.openBrowser, .markSeen, .markReviewed, .remove])

        let manualBacklog = TaskItem(task: task(id: 2, source: "manual", status: "backlog", url: nil))
        XCTAssertEqual(manualBacklog.availableDetailActions, [.markInProgress, .markDone, .remove])

        let manualInProgress = TaskItem(task: task(id: 3, source: "manual", status: "in progress", url: nil))
        XCTAssertEqual(manualInProgress.availableDetailActions, [.moveToBacklog, .markDone, .remove])

        let issue = TaskItem(task: task(id: 4, source: "issue", url: nil))
        XCTAssertEqual(issue.availableDetailActions, [.remove])
    }

    func testOpenTaskURLInvokesOpenerWithTaskURL() async throws {
        let backend = FakeBackend()
        await backend.setTasks([task(id: 17, source: "pr_review", url: "https://example.com/issue/42", seen: false)])
        let opener = RecordingURLOpener()
        opener.setNextResult(true)
        let model = BackendStatusModel(
            client: backend,
            sleep: immediateSleep,
            openURL: { [opener] url in opener.open(url) }
        )
        await model.refresh()

        await model.openTaskURL(id: 17)

        XCTAssertEqual(opener.opened.map(\.absoluteString), ["https://example.com/issue/42"])
        XCTAssertNil(model.errorForTask(id: 17))
        XCTAssertNil(model.errorMessage)
    }

    func testOpenTaskURLClearsExistingPerTaskError() async throws {
        let backend = FakeBackend()
        await backend.setTasks([task(id: 17, source: "pr_review", url: "https://example.com/issue/42", seen: false)])
        let opener = RecordingURLOpener()
        let model = BackendStatusModel(
            client: backend,
            sleep: immediateSleep,
            openURL: { [opener] url in opener.open(url) }
        )
        await model.refresh()
        await backend.failNext("markTaskDone", message: "done failed")
        await model.markDone(id: 17)
        XCTAssertEqual(model.errorForTask(id: 17)?.message, "done failed")

        await model.openTaskURL(id: 17)

        XCTAssertNil(model.errorForTask(id: 17))
        XCTAssertNil(model.errorMessage)
    }

    func testOpenTaskURLSuccessAfterPriorOpenFailureClearsError() async throws {
        let backend = FakeBackend()
        await backend.setTasks([task(id: 17, source: "pr_review", url: "https://example.com/issue/42", seen: false)])
        let opener = RecordingURLOpener()
        let model = BackendStatusModel(
            client: backend,
            sleep: immediateSleep,
            openURL: { [opener] url in opener.open(url) }
        )
        await model.refresh()
        opener.setNextResult(false)
        await model.openTaskURL(id: 17)
        XCTAssertEqual(model.errorForTask(id: 17)?.code, "client.urlOpenFailed")

        opener.setNextResult(true)
        await model.openTaskURL(id: 17)

        XCTAssertNil(model.errorForTask(id: 17))
        XCTAssertNil(model.errorMessage)
    }

    func testOpenTaskURLFailureRecordsPerTaskError() async throws {
        let backend = FakeBackend()
        await backend.setTasks([task(id: 17, source: "pr_review", url: "https://example.com/issue/42", seen: false)])
        let opener = RecordingURLOpener()
        let model = BackendStatusModel(
            client: backend,
            sleep: immediateSleep,
            openURL: { [opener] url in opener.open(url) }
        )
        await model.refresh()
        opener.setNextResult(false)
        let tasksBefore = model.tasks

        await model.openTaskURL(id: 17)

        XCTAssertEqual(model.errorForTask(id: 17)?.code, "client.urlOpenFailed")
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.tasks, tasksBefore)
        XCTAssertEqual(opener.opened.map(\.absoluteString), ["https://example.com/issue/42"])
    }

    func testOpenTaskURLNoOpsWhenTaskHasNoURL() async throws {
        let backend = FakeBackend()
        await backend.setTasks([task(id: 17, source: "manual", status: "backlog", url: nil)])
        let opener = RecordingURLOpener()
        let model = BackendStatusModel(
            client: backend,
            sleep: immediateSleep,
            openURL: { [opener] url in opener.open(url) }
        )
        await model.refresh()

        // Self-document the no-URL availability gate.
        XCTAssertFalse(model.tasks[0].availableDetailActions.contains(.openBrowser))

        await model.openTaskURL(id: 17)

        XCTAssertTrue(opener.opened.isEmpty)
        XCTAssertEqual(model.errorForTask(id: 17)?.code, "client.taskHasNoURL")
    }

    func testOpenTaskURLNoOpsForUnknownTaskID() async throws {
        let backend = FakeBackend()
        await backend.setTasks([])
        let opener = RecordingURLOpener()
        let model = BackendStatusModel(
            client: backend,
            sleep: immediateSleep,
            openURL: { [opener] url in opener.open(url) }
        )
        await model.refresh()
        let errorsBefore = model.taskActionErrors

        await model.openTaskURL(id: 999)

        XCTAssertTrue(opener.opened.isEmpty)
        XCTAssertNil(model.taskActionErrors[999])
        XCTAssertEqual(model.taskActionErrors, errorsBefore)
    }

    func testOpenTaskURLDoesNotChangeIsLoading() async throws {
        let backend = FakeBackend()
        await backend.setTasks([task(id: 17, source: "pr_review", url: "https://example.com/issue/42", seen: false)])
        let opener = RecordingURLOpener()
        let model = BackendStatusModel(
            client: backend,
            sleep: immediateSleep,
            openURL: { [opener] url in opener.open(url) }
        )
        await model.refresh()
        XCTAssertFalse(model.isLoading)

        await model.openTaskURL(id: 17)

        XCTAssertFalse(model.isLoading)
    }

    func testRefreshClearsOpenTaskURLError() async throws {
        let backend = FakeBackend()
        await backend.setTasks([task(id: 17, source: "pr_review", url: "https://example.com/issue/42", seen: false)])
        let opener = RecordingURLOpener()
        let model = BackendStatusModel(
            client: backend,
            sleep: immediateSleep,
            openURL: { [opener] url in opener.open(url) }
        )
        await model.refresh()
        opener.setNextResult(false)
        await model.openTaskURL(id: 17)
        XCTAssertEqual(model.errorForTask(id: 17)?.code, "client.urlOpenFailed")

        await model.refresh()

        XCTAssertNil(model.errorForTask(id: 17))
        XCTAssertTrue(model.taskActionErrors.isEmpty)
    }

    func testSelectWorkspaceClearsOpenTaskURLError() async throws {
        let backend = FakeBackend()
        await backend.setTasks([task(id: 17, source: "pr_review", url: "https://example.com/issue/42", seen: false)])
        let opener = RecordingURLOpener()
        let model = BackendStatusModel(
            client: backend,
            sleep: immediateSleep,
            openURL: { [opener] url in opener.open(url) }
        )
        await model.refresh()
        opener.setNextResult(false)
        await model.openTaskURL(id: 17)
        XCTAssertEqual(model.errorForTask(id: 17)?.code, "client.urlOpenFailed")

        await backend.setTasks([task(id: 22, title: "Org task", source: "manual")])
        await model.selectWorkspace(id: "example-org")

        XCTAssertNil(model.errorForTask(id: 17))
        XCTAssertTrue(model.taskActionErrors.isEmpty)
    }

    func testApplyFiltersSendsExactPayload() async throws {
        let backend = FakeBackend()
        await backend.setTasks([task(id: 17)])
        let model = BackendStatusModel(client: backend, sleep: immediateSleep)
        await model.refresh()

        let filters = TaskListFilters(
            source: "pr_review",
            status: "review received",
            project: "agendum",
            includeSeen: false,
            limit: 100
        )
        await model.applyFilters(filters)

        let call = await backend.lastListTasksCall
        XCTAssertEqual(
            call,
            ListTasksCall(source: "pr_review", status: "review received", project: "agendum", includeSeen: false, limit: 100)
        )
    }

    func testApplyFiltersTriggersExactlyOneReload() async throws {
        let backend = FakeBackend()
        await backend.setTasks([task(id: 17)])
        let model = BackendStatusModel(client: backend, sleep: immediateSleep)
        await model.refresh()

        let callsBefore = await backend.calls
        let listCountBefore = callsBefore.filter { $0 == "listTasks" }.count

        await model.applyFilters(TaskListFilters(status: "open"))

        let callsAfter = await backend.calls
        let listCountAfter = callsAfter.filter { $0 == "listTasks" }.count
        XCTAssertEqual(listCountAfter, listCountBefore + 1)
        XCTAssertEqual(callsAfter.last, "listTasks")
    }

    func testApplyFiltersIsNoOpWhenFiltersUnchanged() async throws {
        let backend = FakeBackend()
        await backend.setTasks([task(id: 17)])
        let model = BackendStatusModel(client: backend, sleep: immediateSleep)
        await model.refresh()

        let callsBefore = await backend.calls
        let listCountBefore = callsBefore.filter { $0 == "listTasks" }.count

        await model.applyFilters(.default)

        let callsAfter = await backend.calls
        let listCountAfter = callsAfter.filter { $0 == "listTasks" }.count
        XCTAssertEqual(listCountAfter, listCountBefore)
    }

    func testApplyFiltersDefaultClearsAllFilters() async throws {
        let backend = FakeBackend()
        await backend.setTasks([task(id: 17)])
        let model = BackendStatusModel(client: backend, sleep: immediateSleep)
        await model.refresh()

        await model.applyFilters(TaskListFilters(
            source: "pr_review",
            status: "open",
            project: "agendum",
            includeSeen: false,
            limit: 100
        ))
        await model.applyFilters(.default)

        let call = await backend.lastListTasksCall
        XCTAssertEqual(
            call,
            ListTasksCall(source: nil, status: nil, project: nil, includeSeen: true, limit: 50)
        )
    }

    func testSelectWorkspaceResetsFilters() async throws {
        let backend = FakeBackend()
        await backend.setTasks([task(id: 17)])
        let model = BackendStatusModel(client: backend, sleep: immediateSleep)
        await model.refresh()

        await model.applyFilters(TaskListFilters(
            source: "pr_review",
            status: "open",
            project: "agendum",
            includeSeen: false,
            limit: 100
        ))

        await backend.setTasks([task(id: 22, title: "Org task", source: "manual")])
        await model.selectWorkspace(id: "example-org")

        XCTAssertEqual(model.filters, .default)
        let call = await backend.lastListTasksCall
        XCTAssertEqual(
            call,
            ListTasksCall(source: nil, status: nil, project: nil, includeSeen: true, limit: 50)
        )
    }

    func testSelectWorkspaceFailureAlsoResetsFilters() async throws {
        let backend = FakeBackend()
        await backend.setTasks([task(id: 17)])
        let model = BackendStatusModel(client: backend, sleep: immediateSleep)
        await model.refresh()

        await model.applyFilters(TaskListFilters(status: "open", limit: 100))
        await backend.failNext("selectWorkspace", message: "select failed")

        await model.selectWorkspace(id: "example-org")

        XCTAssertEqual(model.filters, .default)
        XCTAssertNotNil(model.error)
    }

    func testApplyFiltersFailureSetsGlobalErrorAndPreservesFilters() async throws {
        let backend = FakeBackend()
        await backend.setTasks([task(id: 17)])
        let model = BackendStatusModel(client: backend, sleep: immediateSleep)
        await model.refresh()

        await model.applyFilters(TaskListFilters(status: "open"))
        await backend.failNext("listTasks", message: "list failed")

        let attempted = TaskListFilters(status: "review received", limit: 100)
        await model.applyFilters(attempted)

        XCTAssertNotNil(model.error?.message)
        XCTAssertEqual(model.taskActionErrors, [:])
        XCTAssertEqual(model.filters, attempted)
    }

    func testRefreshUsesCurrentFilters() async throws {
        let backend = FakeBackend()
        await backend.setTasks([task(id: 17)])
        let model = BackendStatusModel(client: backend, sleep: immediateSleep)
        await model.refresh()

        let filters = TaskListFilters(source: "manual", status: "done", limit: 25)
        await model.applyFilters(filters)
        await backend.resetCalls()

        await model.refresh()

        let call = await backend.lastListTasksCall
        XCTAssertEqual(
            call,
            ListTasksCall(source: "manual", status: "done", project: nil, includeSeen: true, limit: 25)
        )
    }

    func testForceSyncUsesCurrentFilters() async throws {
        let backend = FakeBackend()
        await backend.setTasks([task(id: 17)])
        let model = BackendStatusModel(client: backend, sleep: immediateSleep)
        await model.refresh()

        let filters = TaskListFilters(source: "pr_authored", limit: 100)
        await model.applyFilters(filters)
        await backend.resetCalls()

        await model.forceSync()

        let call = await backend.lastListTasksCall
        XCTAssertEqual(
            call,
            ListTasksCall(source: "pr_authored", status: nil, project: nil, includeSeen: true, limit: 100)
        )
    }

    func testPerformTaskActionReloadUsesCurrentFilters() async throws {
        let backend = FakeBackend()
        await backend.setTasks([task(id: 17, source: "pr_review", seen: false)])
        let model = BackendStatusModel(client: backend, sleep: immediateSleep)
        await model.refresh()

        let filters = TaskListFilters(status: "review received", limit: 25)
        await model.applyFilters(filters)
        await backend.resetCalls()

        await model.markSeen(id: 17)

        let call = await backend.lastListTasksCall
        XCTAssertEqual(
            call,
            ListTasksCall(source: nil, status: "review received", project: nil, includeSeen: true, limit: 25)
        )
    }

    func testCreateManualTaskReloadHonorsActiveFilters() async throws {
        let backend = FakeBackend()
        await backend.setTasks([task(id: 99, title: "Created", source: "manual")])
        let model = BackendStatusModel(client: backend, sleep: immediateSleep)
        await model.refresh()

        let filters = TaskListFilters(source: "manual", limit: 100)
        await model.applyFilters(filters)
        await backend.resetCalls()

        let succeeded = await model.createManualTask(title: "new", project: nil, tags: nil)

        XCTAssertTrue(succeeded)
        XCTAssertEqual(model.tasks.map(\.id), [99])
        let call = await backend.lastListTasksCall
        XCTAssertEqual(
            call,
            ListTasksCall(source: "manual", status: nil, project: nil, includeSeen: true, limit: 100)
        )
    }

    func testInitialFiltersAreDefault() {
        let backend = FakeBackend()
        let model = BackendStatusModel(client: backend, sleep: immediateSleep)
        XCTAssertEqual(model.filters, .default)
    }

    func testListTasksDefaultIsByteIdenticalToPriorBehavior() async throws {
        let backend = FakeBackend()
        await backend.setTasks([task(id: 17)])
        let model = BackendStatusModel(client: backend, sleep: immediateSleep)

        await model.refresh()

        let call = await backend.lastListTasksCall
        XCTAssertEqual(
            call,
            ListTasksCall(source: nil, status: nil, project: nil, includeSeen: true, limit: 50)
        )
    }

    func testTaskActionsIncludingOpenURLDoNotInterfereWithEachOther() async throws {
        let backend = FakeBackend()
        await backend.setTasks([
            task(id: 17, title: "First", source: "manual", status: "backlog"),
            task(id: 23, title: "Second", source: "pr_review", url: "https://example.com/issue/23", seen: false),
        ])
        let opener = RecordingURLOpener()
        let model = BackendStatusModel(
            client: backend,
            sleep: immediateSleep,
            openURL: { [opener] url in opener.open(url) }
        )
        await model.refresh()
        await backend.failNext("markTaskDone", message: "done 17 failed")
        await model.markDone(id: 17)
        XCTAssertEqual(model.errorForTask(id: 17)?.message, "done 17 failed")

        await model.openTaskURL(id: 23)

        XCTAssertEqual(model.errorForTask(id: 17)?.message, "done 17 failed")
        XCTAssertNil(model.errorForTask(id: 23))
        XCTAssertEqual(opener.opened.map(\.absoluteString), ["https://example.com/issue/23"])
    }

    func testRefreshDiagnosticsPopulatesDiagnosticsOnSuccess() async throws {
        let backend = FakeBackend()
        let stub = diagnostics(host: "ghe.example.com", helperPath: ["/usr/bin"])
        await backend.setDiagnostics(stub)
        let model = BackendStatusModel(client: backend, sleep: immediateSleep)

        await model.refreshDiagnostics()

        XCTAssertEqual(model.diagnostics, stub)
        XCTAssertNil(model.diagnosticsError)
    }

    func testRefreshDiagnosticsFailureSurfacesStructuredErrorAndKeepsPriorResult() async throws {
        let backend = FakeBackend()
        let firstResult = diagnostics(host: "github.com")
        await backend.setDiagnostics(firstResult)
        let model = BackendStatusModel(client: backend, sleep: immediateSleep)
        await model.refreshDiagnostics()
        XCTAssertEqual(model.diagnostics, firstResult)

        let payload = BackendErrorPayload(code: "storage.failed", message: "disk denied", detail: nil, recovery: nil)
        await backend.failNextWithError("authDiagnose", error: BackendClientError.helperError(payload))

        await model.refreshDiagnostics()

        XCTAssertEqual(model.diagnostics, firstResult)
        XCTAssertEqual(model.diagnosticsError?.code, "storage.failed")
    }

    func testRefreshDiagnosticsSuccessClearsDiagnosticsError() async throws {
        let backend = FakeBackend()
        await backend.setDiagnostics(diagnostics())
        await backend.failNext("authDiagnose", message: "first failed")
        let model = BackendStatusModel(client: backend, sleep: immediateSleep)
        await model.refreshDiagnostics()
        XCTAssertNotNil(model.diagnosticsError)

        await model.refreshDiagnostics()

        XCTAssertNil(model.diagnosticsError)
        XCTAssertNotNil(model.diagnostics)
    }

    func testRefreshDiagnosticsDoesNotChangeIsLoading() async throws {
        let backend = FakeBackend()
        await backend.setDiagnostics(diagnostics())
        let model = BackendStatusModel(client: backend, sleep: immediateSleep)
        XCTAssertFalse(model.isLoading)

        await model.refreshDiagnostics()

        XCTAssertFalse(model.isLoading)
    }

    func testCopyAuthLoginCommandWritesHelperFormattedString() async throws {
        let backend = FakeBackend()
        let formatted = "GH_CONFIG_DIR='/Users/x/.agendum/gh' gh auth login"
        await backend.setAuth(authUnauthenticated(repairCommand: formatted))
        await backend.setTasks([])
        let pasteboard = RecordingPasteboard()
        let model = BackendStatusModel(
            client: backend,
            sleep: immediateSleep,
            pasteboard: { [pasteboard] string in pasteboard.write(string) }
        )
        await model.refresh()

        model.copyAuthLoginCommand()

        XCTAssertEqual(pasteboard.writes, [formatted])
    }

    func testCopyAuthLoginCommandNoOpsWhenAuthMissing() async throws {
        let backend = FakeBackend()
        let pasteboard = RecordingPasteboard()
        let model = BackendStatusModel(
            client: backend,
            sleep: immediateSleep,
            pasteboard: { [pasteboard] string in pasteboard.write(string) }
        )

        model.copyAuthLoginCommand()

        XCTAssertTrue(pasteboard.writes.isEmpty)
    }

    func testCopyAuthLoginCommandIsNoOpWhenRepairCommandIsNil() async throws {
        let backend = FakeBackend()
        await backend.setAuth(authUnauthenticated(repairCommand: nil))
        await backend.setTasks([])
        let pasteboard = RecordingPasteboard()
        let model = BackendStatusModel(
            client: backend,
            sleep: immediateSleep,
            pasteboard: { [pasteboard] string in pasteboard.write(string) }
        )
        await model.refresh()

        model.copyAuthLoginCommand()

        XCTAssertTrue(pasteboard.writes.isEmpty)
    }

    func testOpenGHInstallURLInvokesOpenerWithCanonicalURL() async throws {
        let backend = FakeBackend()
        let opener = RecordingURLOpener()
        opener.setNextResult(true)
        let model = BackendStatusModel(
            client: backend,
            sleep: immediateSleep,
            openURL: { [opener] url in opener.open(url) }
        )

        model.openGHInstallURL()

        XCTAssertEqual(opener.opened.map(\.absoluteString), ["https://cli.github.com/"])
    }

    func testRefreshDiagnosticsFailureKeepsGlobalErrorClean() async throws {
        let backend = FakeBackend()
        await backend.failNext("authDiagnose", message: "diag failed")
        let model = BackendStatusModel(client: backend, sleep: immediateSleep)

        await model.refreshDiagnostics()

        XCTAssertNil(model.error)
        XCTAssertNotNil(model.diagnosticsError)
    }

    func testFakeBackendAuthDiagnoseInvocationCount() async throws {
        let backend = FakeBackend()
        await backend.setDiagnostics(diagnostics())
        let model = BackendStatusModel(client: backend, sleep: immediateSleep)

        await model.refreshDiagnostics()

        let calls = await backend.calls
        XCTAssertEqual(calls.filter { $0 == "authDiagnose" }.count, 1)
    }

    func testRefreshDiagnosticsBeforeRefreshPopulatesDiagnostics() async throws {
        let backend = FakeBackend()
        await backend.setDiagnostics(diagnostics())
        let model = BackendStatusModel(client: backend, sleep: immediateSleep)

        await model.refreshDiagnostics()

        XCTAssertNotNil(model.diagnostics)
        XCTAssertNil(model.auth)
    }

    // MARK: - Item 4: keyboard shortcuts + menu coverage

    func testSetSelectedTaskIDUpdatesPublishedValue() async throws {
        let backend = FakeBackend()
        let model = BackendStatusModel(client: backend, sleep: immediateSleep)

        model.setSelectedTaskID(17)
        XCTAssertEqual(model.selectedTaskID, 17)

        model.setSelectedTaskID(nil)
        XCTAssertNil(model.selectedTaskID)
    }

    func testInitialSelectedTaskIDIsNil() {
        let backend = FakeBackend()
        let model = BackendStatusModel(client: backend, sleep: immediateSleep)
        XCTAssertNil(model.selectedTaskID)
    }

    func testMenuOpenInBrowserCommandInvokesOpenTaskURLForSelectedTask() async throws {
        let backend = FakeBackend()
        await backend.setTasks([task(id: 42, source: "pr_review", url: "https://example.com/issue/42", seen: false)])
        let opener = RecordingURLOpener()
        opener.setNextResult(true)
        let model = BackendStatusModel(
            client: backend,
            sleep: immediateSleep,
            openURL: { [opener] url in opener.open(url) }
        )
        await model.refresh()
        model.setSelectedTaskID(42)

        await TaskDashboardCommands.standard.menuOpenInBrowser.perform(on: model)

        XCTAssertEqual(opener.opened.map(\.absoluteString), ["https://example.com/issue/42"])
    }

    func testMenuMarkSeenCommandInvokesMarkSeenForSelectedTask() async throws {
        let backend = FakeBackend()
        await backend.setTasks([task(id: 42, source: "pr_review", seen: false)])
        let model = BackendStatusModel(client: backend, sleep: immediateSleep)
        await model.refresh()
        await backend.resetCalls()
        model.setSelectedTaskID(42)

        await TaskDashboardCommands.standard.menuMarkSeen.perform(on: model)

        let calls = await backend.calls
        XCTAssertTrue(calls.contains("markTaskSeen:42"))
    }

    func testMenuMarkReviewedCommandInvokesMarkReviewedForSelectedTask() async throws {
        let backend = FakeBackend()
        await backend.setTasks([task(id: 42, source: "pr_review", seen: false)])
        let model = BackendStatusModel(client: backend, sleep: immediateSleep)
        await model.refresh()
        await backend.resetCalls()
        model.setSelectedTaskID(42)

        await TaskDashboardCommands.standard.menuMarkReviewed.perform(on: model)

        let calls = await backend.calls
        XCTAssertTrue(calls.contains("markTaskReviewed:42"))
    }

    func testMenuMarkInProgressCommandInvokesMarkInProgressForSelectedTask() async throws {
        let backend = FakeBackend()
        await backend.setTasks([task(id: 42, source: "manual", status: "backlog")])
        let model = BackendStatusModel(client: backend, sleep: immediateSleep)
        await model.refresh()
        await backend.resetCalls()
        model.setSelectedTaskID(42)

        await TaskDashboardCommands.standard.menuMarkInProgress.perform(on: model)

        let calls = await backend.calls
        XCTAssertTrue(calls.contains("markTaskInProgress:42"))
    }

    func testMenuMoveToBacklogCommandInvokesMoveToBacklogForSelectedTask() async throws {
        let backend = FakeBackend()
        await backend.setTasks([task(id: 42, source: "manual", status: "in progress")])
        let model = BackendStatusModel(client: backend, sleep: immediateSleep)
        await model.refresh()
        await backend.resetCalls()
        model.setSelectedTaskID(42)

        await TaskDashboardCommands.standard.menuMoveToBacklog.perform(on: model)

        let calls = await backend.calls
        XCTAssertTrue(calls.contains("moveTaskToBacklog:42"))
    }

    func testMenuMarkDoneCommandInvokesMarkDoneForSelectedTask() async throws {
        let backend = FakeBackend()
        await backend.setTasks([task(id: 42, source: "manual", status: "backlog")])
        let model = BackendStatusModel(client: backend, sleep: immediateSleep)
        await model.refresh()
        await backend.resetCalls()
        model.setSelectedTaskID(42)

        await TaskDashboardCommands.standard.menuMarkDone.perform(on: model)

        let calls = await backend.calls
        XCTAssertTrue(calls.contains("markTaskDone:42"))
    }

    func testMenuRemoveCommandInvokesRemoveTaskForSelectedTask() async throws {
        let backend = FakeBackend()
        await backend.setTasks([task(id: 42, source: "manual")])
        let model = BackendStatusModel(client: backend, sleep: immediateSleep)
        await model.refresh()
        await backend.resetCalls()
        model.setSelectedTaskID(42)

        await TaskDashboardCommands.standard.menuRemove.perform(on: model)

        let calls = await backend.calls
        XCTAssertTrue(calls.contains("removeTask:42"))
    }

    func testMenuPerTaskCommandsNoOpWhenNoSelection() async throws {
        let perTaskCommands: [(TaskDashboardCommand, String)] = [
            (.openInBrowser, "openInBrowser"),
            (.markSeen, "markTaskSeen"),
            (.markReviewed, "markTaskReviewed"),
            (.markInProgress, "markTaskInProgress"),
            (.moveToBacklog, "moveTaskToBacklog"),
            (.markDone, "markTaskDone"),
            (.remove, "removeTask"),
        ]

        for (command, methodToken) in perTaskCommands {
            let backend = FakeBackend()
            await backend.setTasks([task(id: 42, source: "manual", url: "https://example.com/x", seen: false)])
            let opener = RecordingURLOpener()
            let model = BackendStatusModel(
                client: backend,
                sleep: immediateSleep,
                openURL: { [opener] url in opener.open(url) }
            )
            await model.refresh()
            await backend.resetCalls()
            // Selection is intentionally nil
            XCTAssertNil(model.selectedTaskID, "\(methodToken) precondition")

            await command.perform(on: model)

            let calls = await backend.calls
            XCTAssertFalse(
                calls.contains(where: { $0.hasPrefix(methodToken) }),
                "command \(methodToken) should be a no-op when selection is nil; calls=\(calls)"
            )
            XCTAssertTrue(opener.opened.isEmpty, "\(methodToken) opener should not fire")
        }
    }

    func testMenuMarkSeenCommandTargetsSelectedTaskNotFirstTask() async throws {
        let backend = FakeBackend()
        await backend.setTasks([
            task(id: 10, source: "pr_review", seen: false),
            task(id: 42, source: "pr_review", seen: false),
        ])
        let model = BackendStatusModel(client: backend, sleep: immediateSleep)
        await model.refresh()
        await backend.resetCalls()
        model.setSelectedTaskID(42)

        await TaskDashboardCommands.standard.menuMarkSeen.perform(on: model)

        let calls = await backend.calls
        XCTAssertTrue(calls.contains("markTaskSeen:42"))
        XCTAssertFalse(calls.contains("markTaskSeen:10"))
    }

    func testPerTaskCommandAvailabilityFalseWhenNoSelection() async throws {
        let backend = FakeBackend()
        await backend.setTasks([task(id: 42, source: "manual", url: "https://example.com/x", seen: false)])
        let model = BackendStatusModel(client: backend, sleep: immediateSleep)
        await model.refresh()

        let perTask: [TaskDashboardCommand] = [
            .openInBrowser, .markSeen, .markReviewed, .markInProgress,
            .moveToBacklog, .markDone, .remove,
        ]
        for command in perTask {
            XCTAssertFalse(command.availability(on: model), "\(command) should be unavailable with nil selection")
        }
    }

    func testPerTaskCommandAvailabilityFalseWhenSelectedTaskNotInList() async throws {
        let backend = FakeBackend()
        await backend.setTasks([task(id: 42, source: "manual")])
        let model = BackendStatusModel(client: backend, sleep: immediateSleep)
        await model.refresh()
        model.setSelectedTaskID(999)

        let perTask: [TaskDashboardCommand] = [
            .openInBrowser, .markSeen, .markReviewed, .markInProgress,
            .moveToBacklog, .markDone, .remove,
        ]
        for command in perTask {
            XCTAssertFalse(command.availability(on: model), "\(command) should be unavailable when selection missing from tasks")
        }
    }

    func testOpenInBrowserAvailabilityHonorsAvailableDetailActions() async throws {
        let backend = FakeBackend()
        await backend.setTasks([
            task(id: 10, source: "pr_review", url: "https://example.com/10", seen: false),
            task(id: 11, source: "manual", status: "backlog", url: nil),
        ])
        let model = BackendStatusModel(client: backend, sleep: immediateSleep)
        await model.refresh()

        model.setSelectedTaskID(10)
        XCTAssertTrue(TaskDashboardCommands.standard.menuOpenInBrowser.availability(on: model))

        model.setSelectedTaskID(11)
        XCTAssertFalse(TaskDashboardCommands.standard.menuOpenInBrowser.availability(on: model))
    }

    func testMarkSeenAvailabilityHonorsAvailableDetailActions() async throws {
        let backend = FakeBackend()
        await backend.setTasks([
            task(id: 10, source: "pr_review", seen: false),
            task(id: 11, source: "pr_review", seen: true),
        ])
        let model = BackendStatusModel(client: backend, sleep: immediateSleep)
        await model.refresh()

        model.setSelectedTaskID(10)
        XCTAssertTrue(TaskDashboardCommands.standard.menuMarkSeen.availability(on: model))

        model.setSelectedTaskID(11)
        XCTAssertFalse(TaskDashboardCommands.standard.menuMarkSeen.availability(on: model))
    }

    func testMarkReviewedAvailabilityHonorsSourceGate() async throws {
        let backend = FakeBackend()
        await backend.setTasks([
            task(id: 10, source: "pr_review", seen: true),
            task(id: 11, source: "pr_authored", seen: true),
        ])
        let model = BackendStatusModel(client: backend, sleep: immediateSleep)
        await model.refresh()

        model.setSelectedTaskID(10)
        XCTAssertTrue(TaskDashboardCommands.standard.menuMarkReviewed.availability(on: model))

        model.setSelectedTaskID(11)
        XCTAssertFalse(TaskDashboardCommands.standard.menuMarkReviewed.availability(on: model))
    }

    func testMarkInProgressAndMoveToBacklogAvailabilityToggleByStatus() async throws {
        let backend = FakeBackend()
        await backend.setTasks([
            task(id: 10, source: "manual", status: "in progress"),
            task(id: 11, source: "manual", status: "backlog"),
        ])
        let model = BackendStatusModel(client: backend, sleep: immediateSleep)
        await model.refresh()

        model.setSelectedTaskID(10)
        XCTAssertTrue(TaskDashboardCommands.standard.menuMoveToBacklog.availability(on: model))
        XCTAssertFalse(TaskDashboardCommands.standard.menuMarkInProgress.availability(on: model))

        model.setSelectedTaskID(11)
        XCTAssertTrue(TaskDashboardCommands.standard.menuMarkInProgress.availability(on: model))
        XCTAssertFalse(TaskDashboardCommands.standard.menuMoveToBacklog.availability(on: model))
    }

    func testMarkDoneAndRemoveAvailabilityForManualTask() async throws {
        let backend = FakeBackend()
        await backend.setTasks([
            task(id: 10, source: "manual", status: "backlog"),
            task(id: 11, source: "pr_review", seen: true),
        ])
        let model = BackendStatusModel(client: backend, sleep: immediateSleep)
        await model.refresh()

        model.setSelectedTaskID(10)
        XCTAssertTrue(TaskDashboardCommands.standard.menuMarkDone.availability(on: model))
        XCTAssertTrue(TaskDashboardCommands.standard.menuRemove.availability(on: model))

        model.setSelectedTaskID(11)
        XCTAssertFalse(TaskDashboardCommands.standard.menuMarkDone.availability(on: model))
        XCTAssertTrue(TaskDashboardCommands.standard.menuRemove.availability(on: model))
    }

    func testNewTaskCommandPerformIsNoOp() async throws {
        let backend = FakeBackend()
        await backend.setTasks([task(id: 42)])
        let model = BackendStatusModel(client: backend, sleep: immediateSleep)
        await model.refresh()
        await backend.resetCalls()

        await TaskDashboardCommands.standard.menuNewTask.perform(on: model)

        let calls = await backend.calls
        XCTAssertEqual(calls, [])
    }

    func testNewTaskCommandAvailabilityTracksIsLoading() async throws {
        let backend = FakeBackend()
        let model = BackendStatusModel(client: backend, sleep: immediateSleep)
        XCTAssertFalse(model.isLoading)
        XCTAssertTrue(TaskDashboardCommands.standard.menuNewTask.availability(on: model))
    }

    func testStandardCommandsExposesEveryNamedSlot() {
        let commands = TaskDashboardCommands.standard
        XCTAssertEqual(commands.toolbarRefresh, .refresh)
        XCTAssertEqual(commands.toolbarSync, .sync)
        XCTAssertEqual(commands.menuRefresh, .refresh)
        XCTAssertEqual(commands.menuSync, .sync)
        XCTAssertEqual(commands.menuNewTask, .newTask)
        XCTAssertEqual(commands.menuOpenInBrowser, .openInBrowser)
        XCTAssertEqual(commands.menuMarkSeen, .markSeen)
        XCTAssertEqual(commands.menuMarkReviewed, .markReviewed)
        XCTAssertEqual(commands.menuMarkInProgress, .markInProgress)
        XCTAssertEqual(commands.menuMoveToBacklog, .moveToBacklog)
        XCTAssertEqual(commands.menuMarkDone, .markDone)
        XCTAssertEqual(commands.menuRemove, .remove)
    }
}

private final class RecordingPasteboard: @unchecked Sendable {
    private let lock = NSLock()
    private var _writes: [String] = []

    var writes: [String] {
        lock.lock(); defer { lock.unlock() }
        return _writes
    }

    func write(_ string: String) {
        lock.lock(); defer { lock.unlock() }
        _writes.append(string)
    }
}

private final class RecordingURLOpener: @unchecked Sendable {
    private let lock = NSLock()
    private var _opened: [URL] = []
    private var _nextResult: Bool = true

    var opened: [URL] {
        lock.lock(); defer { lock.unlock() }
        return _opened
    }

    func setNextResult(_ value: Bool) {
        lock.lock(); defer { lock.unlock() }
        _nextResult = value
    }

    func open(_ url: URL) -> Bool {
        lock.lock(); defer { lock.unlock() }
        _opened.append(url)
        return _nextResult
    }
}

private actor SleepRecorder {
    private(set) var values: [UInt64] = []

    func record(_ value: UInt64) {
        values.append(value)
    }
}

struct ListTasksCall: Equatable {
    let source: String?
    let status: String?
    let project: String?
    let includeSeen: Bool
    let limit: Int
}

private actor FakeBackend: AgendumBackendServicing {
    private(set) var calls: [String] = []
    private(set) var lastListTasksCall: ListTasksCall?
    private var failures: [String: any Error] = [:]
    private var current = workspace(id: "base", namespace: nil, isCurrent: true)
    private var workspaceOptions = [
        workspace(id: "base", namespace: nil, isCurrent: true),
        workspace(id: "example-org", namespace: "example-org", isCurrent: false),
    ]
    private var currentAuth = auth(namespace: nil)
    private var currentSync = sync(state: "idle")
    private var forceSyncResult = sync(state: "idle")
    private var syncStatusQueue: [SyncStatus] = []
    private var currentTasks: [AgendumTask] = []
    private var diagnosticsResult: AuthDiagnostics = diagnostics()

    func resetCalls() {
        calls = []
    }

    func setTasks(_ tasks: [AgendumTask]) {
        currentTasks = tasks
    }

    func setForceSyncStatus(_ status: SyncStatus) {
        forceSyncResult = status
    }

    func setSyncStatusQueue(_ statuses: [SyncStatus]) {
        syncStatusQueue = statuses
    }

    func failNext(_ method: String, message: String) {
        failures[method] = TestError(description: message)
    }

    func failNextWithError(_ method: String, error: any Error) {
        failures[method] = error
    }

    func setSyncStatusOverride(_ status: SyncStatus) {
        currentSync = status
    }

    func currentWorkspace() async throws -> Workspace {
        try failIfNeeded("currentWorkspace")
        calls.append("currentWorkspace")
        return current
    }

    func listWorkspaces() async throws -> [Workspace] {
        try failIfNeeded("listWorkspaces")
        calls.append("listWorkspaces")
        return workspaceOptions
    }

    func selectWorkspace(namespace: String?) async throws -> WorkspaceSelection {
        calls.append("selectWorkspace:\(namespace ?? "base")")
        try failIfNeeded("selectWorkspace")
        current = workspace(id: namespace ?? "base", namespace: namespace, isCurrent: true)
        workspaceOptions = workspaceOptions.map {
            workspace(id: $0.id, namespace: $0.namespace, isCurrent: $0.namespace == namespace)
        }
        currentAuth = auth(namespace: namespace)
        currentSync = sync(state: "idle")
        return selection(namespace: namespace)
    }

    func listTasks(source: String?, status: String?, project: String?, includeSeen: Bool, limit: Int) async throws -> [AgendumTask] {
        lastListTasksCall = ListTasksCall(
            source: source,
            status: status,
            project: project,
            includeSeen: includeSeen,
            limit: limit
        )
        try failIfNeeded("listTasks")
        calls.append("listTasks")
        return currentTasks
    }

    func getTask(id: Int) async throws -> AgendumTask? {
        try failIfNeeded("getTask")
        calls.append("getTask:\(id)")
        return currentTasks.first { $0.id == id }
    }

    func markTaskReviewed(id: Int) async throws -> AgendumTask {
        try taskAction("markTaskReviewed", id: id)
    }

    func markTaskInProgress(id: Int) async throws -> AgendumTask {
        try taskAction("markTaskInProgress", id: id)
    }

    func moveTaskToBacklog(id: Int) async throws -> AgendumTask {
        try taskAction("moveTaskToBacklog", id: id)
    }

    func markTaskDone(id: Int) async throws -> AgendumTask {
        try taskAction("markTaskDone", id: id)
    }

    func markTaskSeen(id: Int) async throws -> AgendumTask {
        try taskAction("markTaskSeen", id: id)
    }

    func removeTask(id: Int) async throws -> Bool {
        try failIfNeeded("removeTask")
        calls.append("removeTask:\(id)")
        return true
    }

    func syncStatus() async throws -> SyncStatus {
        calls.append("syncStatus")
        try failIfNeeded("syncStatus")
        if !syncStatusQueue.isEmpty {
            currentSync = syncStatusQueue.removeFirst()
        }
        return currentSync
    }

    func forceSync() async throws -> SyncStatus {
        try failIfNeeded("forceSync")
        calls.append("forceSync")
        currentSync = forceSyncResult
        return forceSyncResult
    }

    func authStatus() async throws -> AuthStatus {
        try failIfNeeded("authStatus")
        calls.append("authStatus")
        return currentAuth
    }

    func authDiagnose() async throws -> AuthDiagnostics {
        calls.append("authDiagnose")
        try failIfNeeded("authDiagnose")
        return diagnosticsResult
    }

    func setDiagnostics(_ value: AuthDiagnostics) {
        diagnosticsResult = value
    }

    func setAuth(_ value: AuthStatus) {
        currentAuth = value
    }

    func createManualTask(title: String, project: String?, tags: [String]?) async throws -> AgendumTask {
        let projectLabel = project ?? "nil"
        let tagsLabel = tags.map { "[" + $0.joined(separator: ",") + "]" } ?? "nil"
        calls.append("createManualTask:\(title)|\(projectLabel)|\(tagsLabel)")
        try failIfNeeded("createManualTask")
        return task(id: 99, title: title, source: "manual", status: "backlog", url: nil)
    }

    private func taskAction(_ method: String, id: Int) throws -> AgendumTask {
        calls.append("\(method):\(id)")
        try failIfNeeded(method)
        return currentTasks.first { $0.id == id } ?? task(id: id)
    }

    private func failIfNeeded(_ method: String) throws {
        if let error = failures.removeValue(forKey: method) {
            throw error
        }
    }
}

private struct TestError: Error, CustomStringConvertible {
    let description: String
}

private let immediateSleep: @Sendable (UInt64) async throws -> Void = { _ in }

private func workspace(id: String, namespace: String?, isCurrent: Bool = false) -> Workspace {
    decode(
        """
        {
            "id": "\(id)",
            "namespace": \(namespace.map { "\"\($0)\"" } ?? "null"),
            "displayName": "\(namespace ?? "Base")",
            "configPath": "/tmp/agendum/config.toml",
            "dbPath": "/tmp/agendum/agendum.db",
            "isCurrent": \(isCurrent)
        }
        """
    )
}

private func auth(namespace: String?) -> AuthStatus {
    decode(
        """
        {
            "ghFound": true,
            "ghPath": "/opt/homebrew/bin/gh",
            "authenticated": true,
            "username": "dan",
            "workspaceGhConfigDir": "/tmp/agendum\(namespace.map { "/workspaces/\($0)" } ?? "")/gh",
            "repairInstructions": null,
            "repairCommand": null
        }
        """
    )
}

private func authUnauthenticated(repairCommand: String?) -> AuthStatus {
    let commandJSON = repairCommand.map { "\"\($0)\"" } ?? "null"
    return decode(
        """
        {
            "ghFound": true,
            "ghPath": "/opt/homebrew/bin/gh",
            "authenticated": false,
            "username": null,
            "workspaceGhConfigDir": "/tmp/agendum/gh",
            "repairInstructions": "Run gh auth login.",
            "repairCommand": \(commandJSON)
        }
        """
    )
}

private func diagnostics(
    found: Bool = true,
    version: String? = "gh version 2.50.0",
    host: String = "github.com",
    helperPath: [String] = ["/usr/bin", "/bin"]
) -> AuthDiagnostics {
    let pathJSON = "[" + helperPath.map { "\"\($0)\"" }.joined(separator: ",") + "]"
    let versionJSON = version.map { "\"\($0)\"" } ?? "null"
    return decode(
        """
        {
            "gh": {
                "found": \(found),
                "path": \(found ? "\"/opt/homebrew/bin/gh\"" : "null"),
                "version": \(versionJSON),
                "installed": \(found)
            },
            "auth": {
                "ghFound": true,
                "ghPath": "/opt/homebrew/bin/gh",
                "authenticated": true,
                "username": "dan",
                "workspaceGhConfigDir": "/tmp/agendum/gh",
                "repairInstructions": null,
                "repairCommand": null
            },
            "host": "\(host)",
            "helperPath": \(pathJSON)
        }
        """
    )
}

private func sync(
    state: String,
    changes: Int = 0,
    lastError: String? = nil,
    lastSyncAt: String? = nil,
    hasAttentionItems: Bool = false
) -> SyncStatus {
    decode(
        """
        {
            "state": "\(state)",
            "lastSyncAt": \(lastSyncAt.map { "\"\($0)\"" } ?? "null"),
            "lastError": \(lastError.map { "\"\($0)\"" } ?? "null"),
            "changes": \(changes),
            "hasAttentionItems": \(hasAttentionItems)
        }
        """
    )
}

private func selection(namespace: String?) -> WorkspaceSelection {
    let id = namespace ?? "base"
    let value: WorkspaceSelection = decode(
        """
        {
            "workspace": {
                "id": "\(id)",
                "namespace": \(namespace.map { "\"\($0)\"" } ?? "null"),
                "displayName": "\(namespace ?? "Base")",
                "configPath": "/tmp/agendum/config.toml",
                "dbPath": "/tmp/agendum/agendum.db",
                "isCurrent": true
            },
            "auth": {
                "ghFound": true,
                "ghPath": "/opt/homebrew/bin/gh",
                "authenticated": true,
                "username": "dan",
                "workspaceGhConfigDir": "/tmp/agendum\(namespace.map { "/workspaces/\($0)" } ?? "")/gh",
                "repairInstructions": null
            },
            "sync": {
                "state": "idle",
                "lastSyncAt": null,
                "lastError": null,
                "changes": 0,
                "hasAttentionItems": false
            }
        }
        """
    )
    return value
}

private func task(
    id: Int,
    title: String = "Task",
    source: String = "manual",
    status: String = "backlog",
    url: String? = nil,
    seen: Bool = true
) -> AgendumTask {
    decode(
        """
        {
            "id": \(id),
            "title": "\(title)",
            "source": "\(source)",
            "status": "\(status)",
            "project": "agendum-mac",
            "ghRepo": null,
            "ghUrl": \(url.map { "\"\($0)\"" } ?? "null"),
            "ghNumber": null,
            "ghAuthor": null,
            "ghAuthorName": null,
            "tags": [],
            "seen": \(seen),
            "lastChangedAt": null,
            "updatedAt": null
        }
        """
    )
}

private func decode<Value: Decodable>(_ json: String) -> Value {
    try! JSONDecoder().decode(Value.self, from: Data(json.utf8))
}
