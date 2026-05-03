# Item 3 Design: Settings / Auth-Repair UI

Status: design draft, awaiting reviewer cycle.
Branch: `codex/item-3-settings-auth-repair` (branched from `feature/mac-prototype` at `c29c630`).
Scope reference: `docs/orchestration-plan.md` §Items, item 3.

## 1. Goal

After this lands, a user who launches Agendum from Finder and hits "GitHub CLI missing" or "GitHub auth needed" in the existing `BackendStatusPanel` (`Sources/AgendumMac/AgendumMacApp.swift:271-282`, `authLabel`) can open the macOS Settings scene (`Cmd-,`) and see, for the currently-selected workspace: whether `gh` is installed, the discovered absolute path, the gh executable version, whether `gh auth status` succeeds for the workspace's `GH_CONFIG_DIR`, the GitHub host the helper checked, and the helper-resolved `PATH`. The Settings UI offers three remediation actions when relevant: copy a prepared `GH_CONFIG_DIR=… gh auth login` command to the pasteboard (the same shape the helper already returns as `repairInstructions` at `Backend/agendum_backend/helper.py:439`), open the gh install URL (`https://cli.github.com/`), and refresh the diagnostics. This addresses the Finder-PATH risk recorded in `docs/handoff.md` ("Finder-launched apps do not inherit shell `PATH`, so `gh` discovery cannot assume the terminal environment") by making the actual `PATH` the helper sees observable to the user.

The current `Sources/AgendumMac/AgendumMacApp.swift` already declares `Settings { SettingsView() }` (lines 25-27) but `SettingsView` is a static stub with three hard-coded fields backed by `.constant(...)` (lines 589-599) — no diagnostic data flows in, no actions wire up to the workflow, and no helper call backs it. Item 3 replaces that stub with a real diagnostic + remediation surface.

## 2. Surface area

Files this implementation will touch:

- `Backend/agendum_backend/helper.py`
  - Add an `auth.diagnose` command branch in `handle_request` (after the existing `auth.status` branch at line 121).
  - Add a new `auth_diagnose(state)` function that returns `{gh: {found, path, version, installed}, auth: AuthStatus, host: <string>, helperPath: [<entries>]}`. The `auth` field reuses the existing `auth_status(state)` payload (line 409) so we do not duplicate gh-config-dir / authenticated logic.
  - Add a private `_gh_version(gh_path: Path) -> str | None` helper (parallel to `_gh_username` at line 477).
  - Add a private `_helper_path_entries() -> list[str]` helper that returns `os.environ.get("PATH", "").split(os.pathsep)` filtered for empty strings.
  - Add a private `_default_gh_host() -> str` helper that returns `os.environ.get("GH_HOST", "github.com")`. The Mac app currently has no per-workspace host configuration, so reporting the resolved host is sufficient for the prototype.
  - No change to `_find_gh` (line 452); the diagnostic just reports its result.
- `Sources/AgendumMacCore/BackendClient.swift`
  - Add `AuthDiagnostics` (Decodable, Equatable, Sendable) with nested `GHDiagnostics` (`found`, `path`, `version`, `installed`), the existing `AuthStatus`, `host: String`, and `helperPath: [String]`.
  - Add `func authDiagnose() async throws -> AuthDiagnostics` and a private `AuthDiagnoseResponsePayload` decodable that mirrors the helper response.
- `Sources/AgendumMacWorkflow/TaskWorkflowModel.swift`
  - Extend `AgendumBackendServicing` (line 8) with `func authDiagnose() async throws -> AuthDiagnostics`.
  - Add `@Published public private(set) var diagnostics: AuthDiagnostics?` and `@Published public private(set) var diagnosticsError: PresentedError?` to `BackendStatusModel`.
  - Add a public `refreshDiagnostics()` `@MainActor` method that calls `client.authDiagnose()`, populates `diagnostics` on success, populates `diagnosticsError = PresentedError.from(error)` on failure, and clears `diagnosticsError` on success. It does NOT toggle `isLoading` (rationale in §4.2).
  - Add a public `copyAuthLoginCommand()` method that builds the same string the helper already produces in `auth.status` `repairInstructions` (`GH_CONFIG_DIR=<dir> gh auth login`) using `auth?.workspaceGhConfigDir` from existing model state, and writes it to `NSPasteboard.general`. The pasteboard call is routed through a new `Pasteboarding` seam (default wraps `NSPasteboard.general.declareTypes/.setString`) so tests can assert what was copied without poking AppKit.
  - Add a public `openGHInstallURL()` method that calls the existing `openURL` seam (line 229) with `URL(string: "https://cli.github.com/")!`. Reuses item 1's plumbing; no new `NSWorkspace` call site.
- `Sources/AgendumMac/AgendumMacApp.swift`
  - Replace the `SettingsView` stub at lines 589-599 with a diagnostic + remediation view bound to `BackendStatusModel` via `@EnvironmentObject` (the model is already constructed in `AgendumMacApp` at line 6 with `@StateObject`; we will add `.environmentObject(backendStatus)` to the `WindowGroup` content and to the `Settings` content so the same model is shared).
  - The new `SettingsView` displays gh status (found/path/version/installed), auth status (authenticated, username, workspace gh config dir, host), helper PATH (a `List` of entries), action buttons (Refresh, Copy Login Command, Open Install URL, Reveal Helper PATH-as-text), and a diagnostics-error caption when `diagnosticsError != nil`. Uses `.task` to call `backendStatus.refreshDiagnostics()` on first appear.
  - Accessibility identifiers per existing convention (see §5).
- `Tests/test_backend_helper.py` and `Tests/test_backend_helper_process.py`
  - Backend coverage for `auth.diagnose` across success-with-gh-installed-and-authenticated, gh-not-found, gh-installed-but-unauthenticated, and PATH probe semantics. Subprocess coverage for at least one round-trip through the long-lived JSONL helper.
- `Tests/AgendumMacCoreTests/BackendClientTests.swift`
  - Coverage that the Swift client encodes an empty payload for `auth.diagnose` and decodes the response shape (including nested `gh`).
- `Tests/AgendumMacWorkflowTests/TaskWorkflowModelTests.swift`
  - Coverage for the new model methods, the diagnostics state binding, and the pasteboard/install-URL action wiring against test seams.

No changes expected to:

- `docs/backend-contract.md` for the prototype: the contract today says "auth actions: report `gh` presence/auth status and give repair instructions" (`docs/plan.md:80-81`), and `auth.diagnose` is an additive command. The build phase should append a new `### auth.diagnose` section to `docs/backend-contract.md` describing request `{}` and the response shape, mirroring the existing `### auth.status` block at line 339.
- `Package.swift` (no new targets / products).
- `Sources/AgendumMacCore/BackendClient.swift`'s existing `AuthStatus` type or `authStatus()` method — the new command supplements rather than replaces them. (`refresh()` at line 311 still calls `client.authStatus()`; Settings additionally calls `client.authDiagnose()` for richer info.)
- `.github/workflows/test.yml` — existing gates already exercise the new tests by virtue of `swift test` and the unittest discovery glob.

## 3. Backend changes

All in `Backend/agendum_backend/helper.py`.

### 3.1 New command branch

Append after the `auth.status` branch (line 122):

```python
if command == "auth.diagnose":
    return _success_response(request_id, auth_diagnose(state))
```

### 3.2 `auth_diagnose(state: HelperState) -> dict[str, Any]`

```python
def auth_diagnose(state: HelperState) -> dict[str, Any]:
    gh_path = _find_gh()
    gh_block: dict[str, Any] = {
        "found": gh_path is not None,
        "path": str(gh_path) if gh_path is not None else None,
        "version": _gh_version(gh_path) if gh_path is not None else None,
        "installed": gh_path is not None,
    }
    return {
        "gh": gh_block,
        "auth": auth_status(state),
        "host": _default_gh_host(),
        "helperPath": _helper_path_entries(),
    }
```

Notes:

- `installed` is currently a synonym for `found` (a `gh` binary at a discovered path is, by definition, installed). The pair stays separate in the schema so a future revision can distinguish "executable exists at a configured path" from "gh CLI version is supported" without a contract break.
- `auth_status(state)` already returns the dict shape the Swift `AuthStatus` decodes (`Sources/AgendumMacCore/BackendClient.swift:12-19`). Reusing it keeps the diagnose payload's `auth` block byte-identical to the existing `auth.status` payload.
- The function does not touch state; it is read-only and idempotent.

### 3.3 Helpers

```python
def _gh_version(gh_path: Path) -> str | None:
    result = subprocess.run(
        [str(gh_path), "--version"],
        capture_output=True,
        text=True,
        env=os.environ.copy(),
        check=False,
    )
    if result.returncode != 0:
        return None
    first_line = (result.stdout or "").splitlines()[0] if result.stdout else ""
    return first_line.strip() or None


def _helper_path_entries() -> list[str]:
    raw = os.environ.get("PATH", "")
    return [entry for entry in raw.split(os.pathsep) if entry]


def _default_gh_host() -> str:
    return os.environ.get("GH_HOST", "github.com")
```

`_gh_version` mirrors `_gh_username` (line 477) — same shape, same error handling style. The first-line slice handles `gh version 2.x.y (yyyy-mm-dd)\nhttps://github.com/cli/cli/releases/tag/v2.x.y` output.

### 3.4 Error envelopes

`auth.diagnose` does not introduce new error codes. `auth_diagnose` cannot raise `PayloadError` (no payload validation), `TaskNotFoundError`, `ValueError` from `normalize_namespace`, or `sqlite3.Error` (no DB access). It can transitively raise `OSError` (storage failure inside `auth_status`'s `ensure_workspace_config(paths)` call at helper.py line 411) — that case maps to `storage.failed` via the existing `except OSError` branch (line 159). No new code path needed.

### 3.5 Reuse rather than duplicate

The design deliberately reuses `auth_status(state)` for the `auth` block and reuses `_find_gh()` for `gh` discovery. We do NOT add a parallel discovery routine. If `_find_gh` is later extended (e.g. to consult a user-configured override path), the diagnose command picks it up automatically.

## 4. Workflow target changes

All additions in `Sources/AgendumMacWorkflow/TaskWorkflowModel.swift`.

### 4.1 Diagnostic state

Add to `BackendStatusModel` after line 219:

```swift
@Published public private(set) var diagnostics: AuthDiagnostics?
@Published public private(set) var diagnosticsError: PresentedError?
```

`diagnostics` is `nil` until the first `refreshDiagnostics()` call settles. `diagnosticsError` is set on failure and cleared on success, mirroring the existing `error: PresentedError?` discipline used by `refresh()` (lines 321, 326). We keep it separate from the global `error` so a Settings-only failure does not blank the dashboard's main error caption — the panes are independently presented and a Settings-tab failure should not look like a workspace failure.

### 4.2 `refreshDiagnostics()`

```swift
public func refreshDiagnostics() async {
    do {
        let result = try await client.authDiagnose()
        diagnostics = result
        diagnosticsError = nil
    } catch {
        diagnosticsError = PresentedError.from(error)
    }
}
```

Notes:
- Trigger: SwiftUI `.task` on `SettingsView` first appearance, plus a manual "Refresh" button (§5.2).
- Does NOT toggle `isLoading`. `isLoading` gates the dashboard toolbar's New / Refresh / Sync buttons (`AgendumMacApp.swift:60-87`); a Settings-window diagnostic refresh should not disable dashboard actions in the foreground window. A separate `@Published var isDiagnosing: Bool` could be added later if we ever want to disable the Settings Refresh button while in flight; for the prototype, the helper round-trip is short and we accept the rare double-fire.
- Failure path leaves `diagnostics` populated with the previous successful result (if any), so the user sees stale data plus a recovery hint, rather than an empty pane.

### 4.3 `copyAuthLoginCommand()`

```swift
public typealias Pasteboarding = @Sendable (String) -> Void

public static var defaultPasteboard: Pasteboarding {
    { string in
        let pasteboard = NSPasteboard.general
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString(string, forType: .string)
    }
}

public func copyAuthLoginCommand() {
    guard let dir = auth?.workspaceGhConfigDir else { return }
    pasteboard("GH_CONFIG_DIR=\(dir) gh auth login")
}
```

The `pasteboard` seam is a defaulted initializer parameter parallel to `openURL` (line 229). It is initialized on the designated init alongside the URL opener:

```swift
pasteboard: @escaping Pasteboarding = BackendStatusModel.defaultPasteboard,
```

Stored as `private let pasteboard: Pasteboarding`. The convenience `init()` (line 233) keeps using the default. Note the command uses `auth?.workspaceGhConfigDir` (an existing field on `AuthStatus`) rather than `diagnostics?.auth.workspaceGhConfigDir`, so the user can copy the command even before `refreshDiagnostics()` settles, as long as the dashboard already loaded `auth` via `refresh()`. If neither has settled the call no-ops; the SwiftUI button is disabled in that case (§5.2).

The command we copy is `GH_CONFIG_DIR=<dir> gh auth login`, the same shape the helper already returns at `auth.status.repairInstructions` (`Backend/agendum_backend/helper.py:439`). We do NOT shell-quote the directory: `workspaceGhConfigDir` comes from `_display_path` (helper.py:606) which returns `~/...` or absolute paths without spaces in practice. The reviewer should flag any case where this quoting omission is unsafe.

### 4.4 `openGHInstallURL()`

```swift
public func openGHInstallURL() {
    let url = URL(string: "https://cli.github.com/")!
    _ = openURL(url)
}
```

We discard the `Bool` returned by `openURL` here. Unlike `openTaskURL(id:)` (which surfaces failures via `taskActionErrors`), this is a fixed, well-known URL. If `NSWorkspace` cannot open `https://cli.github.com/`, populating an error map adds little user value over the macOS-level "no default browser" notification the system already raises. Tests assert the seam was invoked with the right URL (§5.3).

### 4.5 `AgendumBackendServicing` extension

Append `func authDiagnose() async throws -> AuthDiagnostics` to the protocol (line 22). The `extension AgendumBackendClient: AgendumBackendServicing {}` (line 26) needs no change because the new `authDiagnose` method on `AgendumBackendClient` already satisfies the protocol once added.

### 4.6 `AuthDiagnostics` (declared in `AgendumMacCore`, used here)

Defined in `Sources/AgendumMacCore/BackendClient.swift` (§5.3 of this doc) so both the client and the workflow target can reference it without circular imports. `AgendumMacWorkflow` already imports `AgendumMacCore` (line 1), so no new imports.

### 4.7 Composition with existing flows

- `refresh()` (line 311) is unchanged. It still calls `client.authStatus()` for the dashboard's `auth` field and does NOT call `authDiagnose`. Diagnostics are Settings-scoped.
- `selectWorkspace(...)` (line 336) does NOT clear `diagnostics` or `diagnosticsError`. Rationale: workspaces share the same `gh` install and helper `PATH`; only the `auth.workspaceGhConfigDir` portion of diagnostics is workspace-specific, and even that is still useful as stale information until the user clicks Refresh. We accept brief staleness over redundant helper round-trips. If reviewer prefers stricter freshness, the alternative is to clear `diagnostics` on workspace switch and force a re-fetch in `SettingsView.task`; deferred.
- `forceSync` and per-task actions are unrelated and unchanged.

## 5. SwiftUI changes

All in `Sources/AgendumMac/AgendumMacApp.swift`.

### 5.1 Scene wiring

The `Settings { ... }` scene already exists at line 25. The shared model needs to be available inside it. Two changes:

```swift
WindowGroup {
    TaskDashboardView(backendStatus: backendStatus, commands: commands)
        .environmentObject(backendStatus)
}
.commands { ... }

Settings {
    SettingsView()
        .environmentObject(backendStatus)
}
```

Justification for `@EnvironmentObject` in `SettingsView` (vs constructor injection): `Settings { ... }` produces a separate scene whose content is constructed by SwiftUI on demand; passing the model into the closure works but `@EnvironmentObject` is the idiomatic SwiftUI pattern for cross-scene shared state and matches how the existing `TaskDashboardView` already takes `@ObservedObject`. Either works; we choose `@EnvironmentObject` to keep `SettingsView`'s public surface independent of the parent.

### 5.2 `SettingsView` layout

Replace lines 589-599 with a tabless single-pane layout (we expect three modest sections — gh, auth, PATH — which fit in one scrolling form better than three tabs). Pseudo-Swift:

```swift
struct SettingsView: View {
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
                    .accessibilityIdentifier("settings-auth-state")
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
                        Text(entry).font(.system(.caption, design: .monospaced))
                    }
                    .accessibilityIdentifier("settings-helper-path")
                } else {
                    Text("—").accessibilityIdentifier("settings-helper-path")
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
                    .disabled(backendStatus.auth?.workspaceGhConfigDir == nil)
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
```

Notes:
- The frame width grows from 420 to 520 to accommodate the PATH list. Both numbers are arbitrary; the prototype-acceptable bar is "fits without horizontal scroll on a 14" MBP."
- The layout is intentionally single-pane (no `TabView`). If reviewer prefers a tabbed Settings (à la Xcode), the shape generalizes cleanly into three `Tab(...)` blocks; deferred.
- Identifiers follow the existing `task-action-*`, `sync-status-*`, `task-list-filter-*` convention (`settings-` prefix is new and will not collide).

### 5.3 No toolbar / menu changes

We do NOT add a menu shortcut for "Open Settings" beyond the macOS-default `Cmd-,`, which `Settings { ... }` provides automatically. Adding a toolbar shortcut (`gear` icon next to Sync) is deferred to item 4 (keyboard shortcuts + menu coverage); `Cmd-,` is sufficient for the prototype and matches every other macOS app.

## 6. Test plan

All test names below. One-line intent each. Tests live in the indicated file.

### 6.1 `Tests/test_backend_helper.py`

1. `test_auth_diagnose_returns_full_payload_when_gh_authenticated` — fake `gh` on PATH that exits 0 for `auth status` and `--version`; assert `gh.found`, `gh.installed`, `gh.path`, `gh.version`, `auth.authenticated`, `host == "github.com"`, and `helperPath` matches `os.environ["PATH"].split(os.pathsep)` filtered for empty entries.
2. `test_auth_diagnose_when_gh_missing_reports_not_found` — clear `AGENDUM_MAC_GH_PATHS` and override `_find_gh` to return `None` (matching existing test patterns at the other `auth.status` tests); assert `gh.found is False`, `gh.path is None`, `gh.version is None`, `auth.ghFound is False`, and helperPath still populated.
3. `test_auth_diagnose_when_gh_installed_but_not_authenticated` — fake `gh` whose `auth status` exits non-zero; assert `gh.found is True`, `gh.version` populated, `auth.authenticated is False`, and `auth.repairInstructions` mirrors the helper's existing `auth.status` repair string at line 439.
4. `test_auth_diagnose_helper_path_filters_empty_entries` — set `PATH` to `"/a::/b:"` (with empty middle), assert `helperPath == ["/a", "/b"]`.
5. `test_auth_diagnose_host_uses_gh_host_env` — set `GH_HOST=ghe.example.com`, assert `host == "ghe.example.com"`.
6. `test_auth_diagnose_host_defaults_to_github_com` — clear `GH_HOST`, assert `host == "github.com"`.
7. `test_auth_diagnose_gh_version_returns_first_line` — fake `gh --version` returning `"gh version 2.50.0 (2024-04-01)\nhttps://example/cli/releases/v2.50.0\n"`; assert `gh.version == "gh version 2.50.0 (2024-04-01)"`.
8. `test_auth_diagnose_gh_version_returns_none_when_command_fails` — fake `gh --version` exit 1; assert `gh.version is None` while `gh.found is True`.

### 6.2 `Tests/test_backend_helper_process.py`

1. `test_auth_diagnose_round_trips_through_jsonl_process` — start the long-lived helper process, send a `auth.diagnose` request, assert the response envelope decodes and `payload.gh` and `payload.helperPath` are present. Pins the helper protocol surface end-to-end.

### 6.3 `Tests/AgendumMacCoreTests/BackendClientTests.swift`

1. `testClientSendsAuthDiagnoseWithEmptyPayload` — write a fake `auth.diagnose` response into the stub helper, call `authDiagnose()`, assert the request encoded an empty payload `{}` and that the returned `AuthDiagnostics` decodes fields including the nested `gh.version` and `helperPath: [String]`.

### 6.4 `Tests/AgendumMacWorkflowTests/TaskWorkflowModelTests.swift`

1. `testRefreshDiagnosticsPopulatesDiagnosticsOnSuccess` — fake backend returns a stub `AuthDiagnostics`; assert `model.diagnostics` matches and `model.diagnosticsError == nil`.
2. `testRefreshDiagnosticsFailureSurfacesStructuredErrorAndKeepsPriorResult` — first call succeeds, second call fails via `failNext("authDiagnose", ...)`; assert `model.diagnostics` still equals the first result and `model.diagnosticsError?.code` matches the mapped helper-payload code.
3. `testRefreshDiagnosticsSuccessClearsDiagnosticsError` — preload a `diagnosticsError` via a failed call, then succeed; assert `model.diagnosticsError == nil` and `model.diagnostics` populated.
4. `testRefreshDiagnosticsDoesNotChangeIsLoading` — pin the §4.2 contract.
5. `testCopyAuthLoginCommandWritesExpectedString` — populate `auth.workspaceGhConfigDir = "~/.agendum/gh"` via a fake `refresh()`; call `copyAuthLoginCommand()`; assert the recording pasteboard saw `"GH_CONFIG_DIR=~/.agendum/gh gh auth login"`.
6. `testCopyAuthLoginCommandNoOpsWhenAuthMissing` — without calling `refresh()`, call `copyAuthLoginCommand()`; assert the recording pasteboard saw zero writes.
7. `testOpenGHInstallURLInvokesOpenerWithCanonicalURL` — `model.openGHInstallURL()`; assert `RecordingURLOpener` (reused from item 1's tests at design 01 §5.1) recorded one URL equal to `https://cli.github.com/`.
8. `testRefreshDiagnosticsFailureKeepsGlobalErrorClean` — fail diagnose; assert `model.error == nil` (the existing global error is reserved for dashboard failures, per §4.1).
9. `testFakeBackendAuthDiagnoseInvocationCount` — pin that `refreshDiagnostics()` issues exactly one `authDiagnose` call to the fake (no double-fetch / no missing fetch).

### 6.5 SwiftUI coverage gap

The `SettingsView` rendering — accessibility identifiers, `LabeledContent` text mapping, `.task` first-fetch — is not exercised by SwiftPM tests; matches the gap documented in `docs/design/01-open-task-url.md` §5.1.1 and `docs/design/02-task-list-filtering.md` §5.4. Manual smoke (§7) covers it.

## 7. Risks / out-of-scope

- **Launching Terminal.app to run `gh auth login`.** Out of scope. A reliable Terminal-launch path requires either an `NSAppleScript` invocation (Automation entitlement, sandbox-hostile) or a `.command`-file dance (write a temp file, set executable, `NSWorkspace.open`). Both are heavier than copy-to-pasteboard, and the user pasting into their existing terminal session is one keystroke and zero new entitlements. Future checkpoint: revisit if user feedback indicates the copy-paste step is a real friction point.
- **Native OAuth flow replacing `gh`.** Out of scope. Replacing `gh auth login` with a native OAuth Device-Flow or web-callback flow is tied to packaging decisions in `docs/packaging.md` (specifically deferred decisions 1, 4, and 7) and would change `docs/backend-contract.md` §`auth.status`. The prototype keeps the `gh`-based path.
- **mDNS / Keychain integration.** Out of scope. The prototype reads `GH_CONFIG_DIR/hosts.yml` via `gh auth status` — Keychain Services and mDNS-discovered local agents are not part of the bridge.
- **First-run onboarding wizard.** Out of scope. Item 3 is a Settings pane (Cmd-,), not a modal first-run flow. A wizard would compose with this work in a later checkpoint.
- **Sandbox / Mac App Store implications.** Deferred per `docs/packaging.md` deferred decisions 1, 8, 9, 10. The Settings UI as designed makes no sandbox-incompatible calls (`NSPasteboard.general.setString` is sandbox-safe; `NSWorkspace.shared.open(URL)` is sandbox-safe; `subprocess.run("gh", ...)` is helper-side and sandbox boundaries are the helper's concern, not the app's). No new entitlements introduced. The Finder-launched `PATH` issue is still real and `PATH` will look different inside an MAS-sandboxed bundle than today's developer-build bundle; the diagnostic surface in §5.2 is specifically designed to make that visible to the user, not to fix it.
- **Editing settings (organizations, sync interval, "mark seen on focus").** Out of scope. The current stub `SettingsView` (lines 589-599) shows three fake editable fields. Item 3 explicitly removes them: none of the three has a backing model field, none is wired to a backend command, and none belongs in a "diagnose / repair gh" pane. Re-introducing real settings is a separate item once the underlying configuration model exists.
- **Stale `diagnostics` after workspace switch.** Accepted (§4.7). The user can click Refresh.
- **Pasteboard contents for multi-byte / spaces in workspace gh-config-dir.** `_display_path` (helper.py:606) returns either `~/relative` or an absolute path. Neither is shell-quoted. If a user's home directory contains spaces (rare on macOS, possible) the copied command will be malformed. Acceptable for the prototype; future checkpoint can shell-quote with `shlex.quote`-equivalent before serializing.
- **Diagnostic refresh race with `refresh()`.** Both `refresh()` and `refreshDiagnostics()` are `@MainActor`-isolated, so writes to `auth` and `diagnostics` serialize correctly. The SwiftUI `Form` re-renders on either publish. No torn state.

## 8. Open questions for orchestrator

1. The helper currently has no per-workspace `host` configuration; `_default_gh_host` reports `GH_HOST` env or `"github.com"`. Acceptable for the prototype, or should the helper resolve the workspace's `GH_CONFIG_DIR/hosts.yml` and report the first key as `host`? Recommendation: ship the env-only version; add YAML inspection only if reviewer or user testing finds the env-only value misleading.
2. Should `refreshDiagnostics()` be invoked automatically by `refresh()` so the dashboard's `BackendStatusPanel` can also surface a "Settings has details" affordance? Recommendation: NO for item 3 — diagnostics are Settings-scoped — and revisit only if real users report they did not find Settings on their own.
3. Should `copyAuthLoginCommand` shell-quote the directory? Recommendation: NO for item 3 (rare-edge-case on macOS, see §7); add `shlex.quote`-style escaping in a follow-up if observed in practice.

### Self-review (five-lens) pass-throughs

- **Correctness.** `auth_diagnose` reuses existing primitives (`_find_gh`, `auth_status`); only new code is `_gh_version`, `_helper_path_entries`, `_default_gh_host`. Each is small, pure (modulo subprocess), and individually tested. The Swift `AuthDiagnostics` type mirrors the response 1:1 with `Decodable` synthesis.
- **Scope discipline.** Surface area is bounded: one new helper command, one new `BackendClient` method, one new model state pair + three methods, one rewritten `SettingsView`. No bridge-protocol breakage. `Package.swift` untouched. `docs/backend-contract.md` gets a small additive section in the build phase. Deferred items are explicitly named in §7.
- **Missing risks.** Added §7 entries for stale-diagnostics across workspace switch, pasteboard quoting on space-bearing home dirs, sandbox/MAS visibility, and the deliberate decision to not auto-launch Terminal.
- **Test strength.** §6 covers backend success / gh-missing / gh-installed-but-unauthenticated / PATH-probe-edge / GH_HOST default & override / version-parse / version-fail-fallback at the helper layer; subprocess JSONL coverage at the process boundary; Swift client request/response shape; workflow-level success / failure / error-isolation / pasteboard / install-URL / no-op-without-auth / global-error-isolation. The pasteboard and URL seams are testable via the same lock-protected `@unchecked Sendable` pattern item 1 established (`docs/design/01-open-task-url.md` §5.1).
- **Consistency with item 1 / item 2.** Same eight-section layout. Same anchored-claim style (file paths + line numbers). Same SwiftUI-coverage-gap call-out. Same validation-gate enumeration referenced (delegated to `docs/orchestration-plan.md` §Validation Gates). Same `@unchecked Sendable` lock-protected test-seam pattern.
