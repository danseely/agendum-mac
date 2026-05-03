# Item 3 Design: Settings / Auth-Repair UI

Status: design draft, awaiting reviewer cycle.
Branch: `codex/item-3-settings-auth-repair` (branched from `feature/mac-prototype` at `c29c630`).
Scope reference: `docs/orchestration-plan.md` §Items, item 3.

## 1. Goal

After this lands, a user who launches Agendum from Finder and hits "GitHub CLI missing" or "GitHub auth needed" in the existing `BackendStatusPanel` (`Sources/AgendumMac/AgendumMacApp.swift:291`; the `authLabel` property is in `Sources/AgendumMacWorkflow/TaskWorkflowModel.swift:271`) can open the macOS Settings scene (`Cmd-,`) and see, for the currently-selected workspace: whether `gh` is installed, the discovered absolute path, the gh executable version, whether `gh auth status` succeeds for the workspace's `GH_CONFIG_DIR`, the GitHub host the helper checked, and the helper-resolved `PATH`. The Settings UI offers three remediation actions when relevant: copy a prepared `GH_CONFIG_DIR=… gh auth login` command to the pasteboard (the same shape the helper already returns as `repairInstructions` at `Backend/agendum_backend/helper.py:439`), open the gh install URL (`https://cli.github.com/`), and refresh the diagnostics. This addresses the Finder-PATH risk recorded in `docs/handoff.md` ("Finder-launched apps do not inherit shell `PATH`, so `gh` discovery cannot assume the terminal environment") by making the actual `PATH` the helper sees observable to the user.

The current `Sources/AgendumMac/AgendumMacApp.swift` already declares `Settings { SettingsView() }` (lines 25-27) but `SettingsView` is a static stub with three hard-coded fields backed by `.constant(...)` (lines 589-599) — no diagnostic data flows in, no actions wire up to the workflow, and no helper call backs it. Item 3 replaces that stub with a real diagnostic + remediation surface.

## 2. Surface area

Files this implementation will touch:

- `Backend/agendum_backend/helper.py`
  - Add an `auth.diagnose` command branch in `handle_request` (after the existing `auth.status` branch at helper.py:121-122).
  - Add a new `auth_diagnose(state)` function that returns `{"diagnostics": {gh: {found, path, version, installed}, auth: AuthStatus, host: <string>, helperPath: [<entries>]}}` (the helper wraps the diagnostic block under a single `diagnostics` key, matching the existing `auth.status` (`{"auth": ...}`) and `workspace.list` wrapping convention). The `auth` field reuses the existing `auth_status(state)` payload (line 409) so we do not duplicate gh-config-dir / authenticated logic.
  - Add a private `_gh_version(gh_path: Path) -> str | None` helper (parallel to `_gh_username` at line 477).
  - Add a private `_helper_path_entries() -> list[str]` helper that returns `os.environ.get("PATH", "").split(os.pathsep)` filtered for empty strings.
  - Add a private `_default_gh_host() -> str` helper that returns `os.environ.get("GH_HOST", "github.com")`. The Mac app currently has no per-workspace host configuration, so reporting the resolved host is sufficient for the prototype.
  - **Fix existing bug at helper.py:439:** the existing `repairInstructions` interpolates `paths.gh_config_dir` unquoted (`f"Run GH_CONFIG_DIR={paths.gh_config_dir} gh auth login in Terminal."`). Introduce a single shared formatter (e.g. `_format_repair_command(gh_config_dir: Path) -> str` returning `f"GH_CONFIG_DIR={shlex.quote(str(gh_config_dir))} gh auth login"`) that produces a runnable shell command.
  - **New field on `AuthStatus`: `repairCommand: Optional[str]`.** Populated **only** in the unauthenticated-with-gh-found branch (helper.py:439) where `_format_repair_command(paths.gh_config_dir)` produces a runnable command. In the gh-missing branch (helper.py:420) `repairCommand` is `None` because the human-readable prose ("Install GitHub CLI with Homebrew, then authenticate with gh auth login.") is not a shell-runnable command and pasting it would not work. In the already-authenticated branch (helper.py:448) `repairCommand` is `None`.
  - The existing `repairInstructions` field is preserved as user-facing prose (rendered as caption text in Settings) since it has recovery value even when no command exists. In the unauthenticated-with-gh-found branch, `repairInstructions` is replaced with a human-readable instruction that references the command (the runnable form lives in `repairCommand`); both fields still reflect a single source of truth for the command shape via `_format_repair_command`. Settings reads the helper-formatted strings verbatim — no Swift-side string assembly.
  - No change to `_find_gh` (line 452); the diagnostic just reports its result.
- `Sources/AgendumMacCore/BackendClient.swift`
  - Extend the existing `AuthStatus` (lines 12-19) with a new optional `repairCommand: String?` field decoded from the helper's `repairCommand` JSON key. The field is `nil` when the helper omits it (gh-missing or already-authenticated branches) and populated in the unauthenticated-with-gh-found branch.
  - Add `AuthDiagnostics` (Decodable, Equatable, Sendable) with nested `GHDiagnostics` (`found`, `path`, `version`, `installed`), the existing `AuthStatus` (now carrying `repairCommand`), `host: String`, and `helperPath: [String]`.
  - Add `func authDiagnose() async throws -> AuthDiagnostics` and a private `AuthDiagnoseResponsePayload` decodable shaped as `{ diagnostics: AuthDiagnostics }` that mirrors the wrapped helper response; `authDiagnose()` decodes the wrapper and returns the inner `diagnostics`.
- `Sources/AgendumMacWorkflow/TaskWorkflowModel.swift`
  - Extend `AgendumBackendServicing` (line 8) with `func authDiagnose() async throws -> AuthDiagnostics`.
  - Add `@Published public private(set) var diagnostics: AuthDiagnostics?` and `@Published public private(set) var diagnosticsError: PresentedError?` to `BackendStatusModel`.
  - Add a public `refreshDiagnostics()` `@MainActor` method that calls `client.authDiagnose()`, populates `diagnostics` on success, populates `diagnosticsError = PresentedError.from(error)` on failure, and clears `diagnosticsError` on success. It does NOT toggle `isLoading` (rationale in §4.2).
  - Add a public `copyAuthLoginCommand()` method that copies the helper-formatted login string verbatim. The string source is `auth?.repairInstructions` (already produced by `_format_repair_command` per §2's helper.py:439 fix); the model does not assemble or shell-quote on the Swift side. The pasteboard call is routed through a new `Pasteboarding` seam (default wraps `NSPasteboard.general.declareTypes/.setString`) so tests can assert what was copied without poking AppKit.
  - Add a public `openGHInstallURL()` method that calls the existing `openURL` seam (line 229) with `URL(string: "https://cli.github.com/")!`. Reuses item 1's plumbing; no new `NSWorkspace` call site.
- `Sources/AgendumMac/AgendumMacApp.swift` (Settings scene only — `WindowGroup` is unchanged because `TaskDashboardView` already takes `backendStatus` via constructor)
  - Replace the `SettingsView` stub at lines 589-599 with a diagnostic + remediation view bound to `BackendStatusModel` via `@EnvironmentObject` (the model is already constructed in `AgendumMacApp` at line 6 with `@StateObject`; we will add `.environmentObject(backendStatus)` to the `Settings` content so the same model is shared with the dashboard scene).
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

Append after the `auth.status` branch (helper.py:121-122):

```python
if command == "auth.diagnose":
    return _success_response(request_id, {"diagnostics": auth_diagnose(state)})
```

The response payload is wrapped under a single `diagnostics` key. This matches the existing `auth.status` response (`{"auth": ...}` at helper.py:122) and the `workspace.list` wrapping convention. The Swift side decodes via a dedicated `AuthDiagnoseResponsePayload { diagnostics: AuthDiagnostics }` type and returns the inner `diagnostics`.

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

`_gh_version` mirrors `_gh_username` (line 477) — same shape, same error handling style. The first-line slice handles `gh version 2.x.y (yyyy-mm-dd)\nhttps://github.com/cli/cli/releases/tag/v2.x.y` output. We omit `env=` because `subprocess.run` already inherits the parent process environment by default; passing `os.environ.copy()` would be redundant.

### 3.4 Error envelopes

`auth.diagnose` does not introduce new error codes. `auth_diagnose` cannot raise `PayloadError` (no payload validation), `TaskNotFoundError`, `ValueError` from `normalize_namespace`, or `sqlite3.Error` (no DB access). It can transitively raise `OSError` (storage failure inside `auth_status`'s `ensure_workspace_config(paths)` call at helper.py line 411) — that case maps to `storage.failed` via the existing `except OSError` branch (line 159). No new code path needed.

### 3.5 Reuse rather than duplicate

The design deliberately reuses `auth_status(state)` for the `auth` block and reuses `_find_gh()` for `gh` discovery. We do NOT add a parallel discovery routine. If `_find_gh` is later extended (e.g. to consult a user-configured override path), the diagnose command picks it up automatically.

`auth.diagnose` invokes `_find_gh()` up to two times (once in `auth_diagnose`, once transitively inside `auth_status`) and `gh` subprocess up to three times (`gh --version`, `gh auth status`, and `gh api user` from `_gh_username`). Acceptable because Settings fires on demand, not per dashboard refresh.

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

The `Pasteboarding` typealias and `defaultPasteboard` static mirror the placement of `URLOpening` (file scope, line 6) and `defaultURLOpener` (inside the `public extension BackendStatusModel` block at line 495). Specifically:

- `public typealias Pasteboarding = @Sendable (String) -> Void` is declared at file scope alongside `URLOpening` (around line 6 of `Sources/AgendumMacWorkflow/TaskWorkflowModel.swift`).
- `public static var defaultPasteboard: Pasteboarding { ... }` lives inside the existing `public extension BackendStatusModel` block (around line 495), alongside `defaultURLOpener`.

```swift
// File scope, alongside URLOpening (line 6):
public typealias Pasteboarding = @Sendable (String) -> Void

// Inside `public extension BackendStatusModel` (line 495), alongside defaultURLOpener:
public static var defaultPasteboard: Pasteboarding {
    { string in
        let pasteboard = NSPasteboard.general
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString(string, forType: .string)
    }
}

// Method on BackendStatusModel:
public func copyAuthLoginCommand() {
    guard let command = auth?.repairCommand else { return }
    pasteboard(command)
}
```

`copyAuthLoginCommand()` runs on `@MainActor` (inherited from `BackendStatusModel`); the default `Pasteboarding` closure calls `NSPasteboard.general` which is documented main-thread-safe.

The `pasteboard` seam is a defaulted initializer parameter parallel to `openURL` (line 229). It is initialized on the designated init alongside the URL opener:

```swift
pasteboard: @escaping Pasteboarding = BackendStatusModel.defaultPasteboard,
```

Stored as `private let pasteboard: Pasteboarding`. The convenience `init()` (line 233) keeps using the default. The command uses `auth?.repairCommand` (the helper-formatted runnable login command, populated only in the unauthenticated-with-gh-found branch) rather than re-assembling the string in Swift, so the user can copy the command even before `refreshDiagnostics()` settles, as long as the dashboard already loaded `auth` via `refresh()`. If `auth` has not settled, or `repairCommand` is `nil` (gh not installed, or already authenticated), the call no-ops; the SwiftUI button is disabled in that case (§5.2).

The command shape is produced helper-side by `_format_repair_command` (§2 helper.py:439 fix), which uses `shlex.quote(str(gh_config_dir))` to quote the directory. The Swift side never assembles or quotes the string. The `repairCommand` field on `AuthStatus` carries the formatter output — single source of truth.

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

The `Settings { ... }` scene already exists at line 25. The shared model needs to be available inside it. The `WindowGroup` content is unchanged — `TaskDashboardView(backendStatus: backendStatus, commands: commands)` already receives the model via constructor, so no `.environmentObject` injection is needed there. Only the `Settings` scene gets the env object:

```swift
Settings {
    SettingsView()
        .environmentObject(backendStatus)
}
```

Justification for `@EnvironmentObject` in `SettingsView` (vs constructor injection): `Settings { ... }` produces a separate scene whose content is constructed by SwiftUI on demand; passing the model into the closure works but `@EnvironmentObject` is the idiomatic SwiftUI pattern for cross-scene shared state. Either works; we choose `@EnvironmentObject` to keep `SettingsView`'s public surface independent of the parent.

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
3. `test_auth_diagnose_when_gh_installed_but_not_authenticated` — fake `gh` whose `auth status` exits non-zero; assert `gh.found is True`, `gh.version` populated, `auth.authenticated is False`, that the unauthenticated `auth.repairCommand` field exactly equals `_format_repair_command(GH_CONFIG_DIR)` output (post-fix shape with `shlex.quote` applied), and that in the gh-missing branch (separate fixture) `auth.repairCommand is None`. Pins that `repairCommand` is populated only when a runnable command exists and that the diagnose payload's `auth` block carries the shared-formatter output verbatim.
4. `test_auth_diagnose_helper_path_filters_empty_entries` — set `PATH` to `"/a::/b:"` (with empty middle), assert `helperPath == ["/a", "/b"]`.
5. `test_auth_diagnose_host_uses_gh_host_env` — set `GH_HOST=ghe.example.com`, assert `host == "ghe.example.com"`.
6. `test_auth_diagnose_host_defaults_to_github_com` — clear `GH_HOST`, assert `host == "github.com"`.
7. `test_auth_diagnose_gh_version_returns_first_line` — fake `gh --version` returning `"gh version 2.50.0 (2024-04-01)\nhttps://example/cli/releases/v2.50.0\n"`; assert `gh.version == "gh version 2.50.0 (2024-04-01)"`.
8. `test_auth_diagnose_gh_version_returns_none_when_command_fails` — fake `gh --version` exit 1; assert `gh.version is None` while `gh.found is True`.
9. `test_auth_diagnose_maps_storage_failure_when_workspace_config_raises` — monkeypatch `ensure_workspace_config` to raise `OSError`; dispatch an `auth.diagnose` request through `handle_request`; assert the response is an error envelope with code `storage.failed` (the existing `except OSError` branch at helper.py:159 already maps this; the test pins the contract that the diagnose path participates in it).
10. `test_format_repair_command_quotes_paths_with_spaces` — assert that for `GH_CONFIG_DIR = "/Users/x/My Stuff/.agendum/gh"`, `_format_repair_command(...)` returns a string containing `'/Users/x/My Stuff/.agendum/gh'` (single-quoted by `shlex.quote`), and that for `GH_CONFIG_DIR = "/Users/x/.agendum/gh"` (no spaces / no shell metacharacters) the returned string is byte-identical to the pre-fix shape — i.e. `shlex.quote` returns the value unchanged and the formatter emits `GH_CONFIG_DIR=/Users/x/.agendum/gh gh auth login` verbatim.
11. `test_auth_status_repair_command_uses_shared_formatter` — call `auth.status` in the unauthenticated branch with a `GH_CONFIG_DIR` containing spaces; assert the `repairCommand` field exactly equals `_format_repair_command(GH_CONFIG_DIR)`. Pins that the helper.py:439 string went through the shared formatter post-fix (single source of truth).
12. `test_gh_version_returns_none_for_empty_stdout_on_exit_zero` — monkeypatch `subprocess.run` so `gh --version` returns exit code 0 with stdout `""`; assert `_gh_version(...)` returns `None` (not `""`). Pins the `first_line.strip() or None` branch in `_gh_version`.

(+4 new Python tests from cycle-1 / cycle-2 / cycle-3 (1 from cycle-1, 2 from cycle-2, 1 from cycle-3); total Python count for §6.1 is 12.)

### 6.2 `Tests/test_backend_helper_process.py`

1. `test_auth_diagnose_round_trips_through_jsonl_process` — start the long-lived helper process, send an `auth.diagnose` request with `payload: {}` (explicitly empty), assert the response envelope decodes, `payload.diagnostics.gh` and `payload.diagnostics.helperPath` are present, and the helper does NOT return `payload.invalid`. Pins both the helper protocol surface end-to-end and the empty-payload contract.

### 6.3 `Tests/AgendumMacCoreTests/BackendClientTests.swift`

1. `testClientSendsAuthDiagnoseWithEmptyPayload` — write a fake `auth.diagnose` response (wrapped under `{"diagnostics": ...}`) into the stub helper, call `authDiagnose()`, assert the request encoded an empty payload `{}`, that the wrapper is decoded, and that the returned `AuthDiagnostics` decodes fields including the nested `gh.version` and `helperPath: [String]`.

### 6.4 `Tests/AgendumMacWorkflowTests/TaskWorkflowModelTests.swift`

1. `testRefreshDiagnosticsPopulatesDiagnosticsOnSuccess` — fake backend returns a stub `AuthDiagnostics`; assert `model.diagnostics` matches and `model.diagnosticsError == nil`.
2. `testRefreshDiagnosticsFailureSurfacesStructuredErrorAndKeepsPriorResult` — first call succeeds, second call fails via `failNext("authDiagnose", ...)`; assert `model.diagnostics` still equals the first result and `model.diagnosticsError?.code` matches the mapped helper-payload code.
3. `testRefreshDiagnosticsSuccessClearsDiagnosticsError` — preload a `diagnosticsError` via a failed call, then succeed; assert `model.diagnosticsError == nil` and `model.diagnostics` populated.
4. `testRefreshDiagnosticsDoesNotChangeIsLoading` — pin the §4.2 contract.
5. `testCopyAuthLoginCommandWritesHelperFormattedString` — populate `auth.repairCommand = "GH_CONFIG_DIR='/Users/x/.agendum/gh' gh auth login"` via a fake `refresh()`; call `copyAuthLoginCommand()`; assert the recording pasteboard saw the verbatim helper-formatted string (no Swift-side reassembly).
6. `testCopyAuthLoginCommandNoOpsWhenAuthMissing` — without calling `refresh()` (so `auth == nil`), call `copyAuthLoginCommand()`; assert the recording pasteboard saw zero writes.
7. `testCopyAuthLoginCommandIsNoOpWhenRepairCommandIsNil` — populate `auth` with `repairCommand == nil` (gh-missing branch shape, where `repairInstructions` carries prose but no runnable command exists); call `copyAuthLoginCommand()`; assert the recording pasteboard saw zero writes. Pins the cycle-3 finding that prose-only auth states must not emit a paste.
8. `testOpenGHInstallURLInvokesOpenerWithCanonicalURL` — `model.openGHInstallURL()`; assert `RecordingURLOpener` (reused from item 1's tests at design 01 §5.1) recorded one URL equal to `https://cli.github.com/`.
9. `testRefreshDiagnosticsFailureKeepsGlobalErrorClean` — fail diagnose; assert `model.error == nil` (the existing global error is reserved for dashboard failures, per §4.1).
10. `testFakeBackendAuthDiagnoseInvocationCount` — pin that `refreshDiagnostics()` issues exactly one `authDiagnose` call to the fake (no double-fetch / no missing fetch).
11. `testRefreshDiagnosticsBeforeRefreshPopulatesDiagnostics` — with a fresh `BackendStatusModel` (no `refresh()` called), invoke `refreshDiagnostics()` directly; assert `model.diagnostics` is populated and `model.auth` (the model's separate property fed by `refresh()`) remains `nil`/untouched. Pins the first-run path where Settings opens before the dashboard's `refresh()` settles.

(+2 new Swift tests from cycle-1 / cycle-3 (1 from cycle-1, 1 from cycle-3); total Swift workflow count for §6.4 is 11.)

### 6.5 SwiftUI coverage gap

The `SettingsView` rendering — accessibility identifiers, `LabeledContent` text mapping, `.task` first-fetch — is not exercised by SwiftPM tests; matches the gap documented in `docs/design/01-open-task-url.md` §5.1.1 and `docs/design/02-task-list-filtering.md` §5.4. Manual smoke (§7) covers it.

## 7. Risks / out-of-scope

- **Launching Terminal.app to run `gh auth login`.** Out of scope. A reliable Terminal-launch path requires either an `NSAppleScript` invocation (Automation entitlement, sandbox-hostile) or a `.command`-file dance (write a temp file, set executable, `NSWorkspace.open`). Both are heavier than copy-to-pasteboard, and the user pasting into their existing terminal session is one keystroke and zero new entitlements. Future checkpoint: revisit if user feedback indicates the copy-paste step is a real friction point.
- **Native OAuth flow replacing `gh`.** Out of scope. Replacing `gh auth login` with a native OAuth Device-Flow or web-callback flow is tied to packaging decisions in `docs/packaging.md` (specifically deferred decisions 1, 4, and 7) and would change `docs/backend-contract.md` §`auth.status`. The prototype keeps the `gh`-based path.
- **mDNS / Keychain integration.** Out of scope. The prototype reads `GH_CONFIG_DIR/hosts.yml` via `gh auth status` — Keychain Services and mDNS-discovered local agents are not part of the bridge.
- **First-run onboarding wizard.** Out of scope. Item 3 is a Settings pane (Cmd-,), not a modal first-run flow. A wizard would compose with this work in a later checkpoint.
- **Sandbox / Mac App Store implications.** Deferred per `docs/packaging.md` deferred decisions 1, 8, 9, 10. The Settings UI as designed makes no sandbox-incompatible calls (`NSPasteboard.general.setString` is sandbox-safe; `NSWorkspace.shared.open(URL)` is sandbox-safe; `subprocess.run("gh", ...)` is helper-side and sandbox boundaries are the helper's concern, not the app's). No new entitlements introduced. The Finder-launched `PATH` issue is still real and `PATH` will look different inside an MAS-sandboxed bundle than today's developer-build bundle; the diagnostic surface in §5.2 is specifically designed to make that visible to the user, not to fix it.
- **Editing settings (organizations, sync interval, "mark seen on focus").** Out of scope. The current stub `SettingsView` (lines 589-599) shows three fake editable fields. Item 3 explicitly removes them: none of the three has a backing model field, none is wired to a backend command, and none belongs in a "diagnose / repair gh" pane. Re-introducing real settings is a separate item once the underlying configuration model exists.
- **Helper-process PATH staleness.** Helper-process PATH is captured at process spawn (`os.environ['PATH']`); clicking Settings → Refresh re-runs `auth.diagnose` inside the same helper process, so PATH changes since launch (e.g. user installs gh after launching the app, or runs `launchctl setenv PATH ...`) will NOT be reflected. The user-visible symptom is a Settings panel that continues to show "GitHub CLI missing" even after a successful install. Mitigation: SettingsView caption (§5.2, "Relaunch Agendum if you've just installed gh — the helper's PATH is captured at launch and won't pick up new installs until restart.") tells the user to relaunch Agendum to pick up a new PATH. Future hardening: re-spawn the helper subprocess from within the app on Refresh, or wire a "Restart helper" action; deferred.
- **Stale `diagnostics` after workspace switch.** Accepted (§4.7). The user can click Refresh.
- **Pasteboard contents for multi-byte / spaces in workspace gh-config-dir.** Resolved this slice via the helper-side `shlex.quote(...)` fix at helper.py:439 (§2). The copied command is now safe for paths containing spaces. The Swift side never assembles the string. For paths without shell metacharacters or spaces, `shlex.quote` returns the value unchanged, so the displayed/copied `repairInstructions` is byte-identical to the pre-fix shape. For paths with spaces or shell metacharacters (rare in practice), the string now wraps in single quotes — a deliberate, safer change.
- **Env-only auth-host mismatch.** If a user authenticates against a non-default host (e.g. `gh auth login --hostname ghe.example.com`) without setting `GH_HOST`, Settings will report `github.com` (from `_default_gh_host`) while `gh auth status` shows `ghe.example.com`. The user-visible symptom is a host mismatch between the displayed host and the auth state. Future hardening: parse `~/.config/gh/hosts.yml` (or the workspace's `GH_CONFIG_DIR/hosts.yml`) to resolve the host. Deferred to a future packaging-decisions checkpoint. Anchored to §8 OQ1 (the env-only recommendation).
- **Diagnostic refresh race with `refresh()`.** Both `refresh()` and `refreshDiagnostics()` are `@MainActor`-isolated, so writes to `auth` and `diagnostics` serialize correctly. The SwiftUI `Form` re-renders on either publish. No torn state.

## 8. Open questions for orchestrator

All three cycle-0 open questions resolved during cycle-1 review (2026-05-03). No questions remain open.

1. **OQ1 — host source.** RESOLVED: ship the env-only version (`_default_gh_host` reports `GH_HOST` or `"github.com"`). The env-only mismatch failure mode is documented as a §7 risk; YAML inspection of `GH_CONFIG_DIR/hosts.yml` is a future-checkpoint hardening, not part of this slice.
2. **OQ2 — auto-fire `refreshDiagnostics` from `refresh`.** RESOLVED: NO. Diagnostics are Settings-scoped; the dashboard does not call `authDiagnose()`. Revisit only if real users report they did not find Settings on their own.
3. **OQ3 — shell-quote `GH_CONFIG_DIR` in copied command.** RESOLVED 2026-05-03: helper-side `shlex.quote(GH_CONFIG_DIR)` fixes both the new copy command and the existing `repairInstructions` bug at helper.py:439. Single shared formatter (`_format_repair_command`) is the source of truth; the Swift side reads the formatted string verbatim. See §2 (helper.py:439 fix) and §4.3.

### Self-review (five-lens) pass-throughs

- **Correctness.** `auth_diagnose` reuses existing primitives (`_find_gh`, `auth_status`); only new code is `_gh_version`, `_helper_path_entries`, `_default_gh_host`. Each is small, pure (modulo subprocess), and individually tested. The Swift `AuthDiagnostics` type mirrors the response 1:1 with `Decodable` synthesis.
- **Scope discipline.** Surface area is bounded: one new helper command, one new `BackendClient` method, one new model state pair + three methods, one rewritten `SettingsView`. No bridge-protocol breakage. `Package.swift` untouched. `docs/backend-contract.md` gets a small additive section in the build phase. Deferred items are explicitly named in §7.
- **Missing risks.** Added §7 entries for stale-diagnostics across workspace switch, pasteboard quoting on space-bearing home dirs, sandbox/MAS visibility, and the deliberate decision to not auto-launch Terminal.
- **Test strength.** §6 covers backend success / gh-missing / gh-installed-but-unauthenticated / PATH-probe-edge / GH_HOST default & override / version-parse / version-fail-fallback at the helper layer; subprocess JSONL coverage at the process boundary; Swift client request/response shape; workflow-level success / failure / error-isolation / pasteboard / install-URL / no-op-without-auth / global-error-isolation. The pasteboard and URL seams are testable via the same lock-protected `@unchecked Sendable` pattern item 1 established (`docs/design/01-open-task-url.md` §5.1).
- **Consistency with item 1 / item 2.** Same eight-section layout. Same anchored-claim style (file paths + line numbers). Same SwiftUI-coverage-gap call-out. Same validation-gate enumeration referenced (delegated to `docs/orchestration-plan.md` §Validation Gates). Same `@unchecked Sendable` lock-protected test-seam pattern.
