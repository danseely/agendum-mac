# Mac GUI Port Plan

## Active goal
Evaluate and prototype a proper native macOS GUI for agendum in a new standalone project.

## Scope
- Keep this project separate from `../agendum`.
- Build a Mac-native shell for the agendum workflow.
- Reuse the existing Python engine where practical.
- Define the backend bridge before committing to a full Swift rewrite.

## Constraints
- Do not modify `../agendum` for GUI work unless explicitly requested.
- Keep public `main` README-only until the prototype is ready to become default-branch content.
- Use `feature/mac-prototype` as the broad prototype integration branch.
- Do not push directly to `feature/mac-prototype`; keep it clean and update it only through PRs unless explicitly requested otherwise.
- Use stacked feature branches, such as `feature/backend-helper`, for reviewable implementation checkpoints.
- Keep the existing terminal app working during any future backend extraction.
- Preserve `gh`-based GitHub behavior unless an explicit decision replaces it.
- Prefer a Mac-native shell, not a generic desktop wrapper.
- Avoid hand-authoring Xcode project internals unless no better generator/template path exists.

## Non-goals
- Do not merge prototype implementation into `main` until explicitly requested.
- No full backend implementation in this repo yet.
- No release/distribution channel has been chosen.
- No decision has been made to rewrite the Python backend in Swift.

## Current recommendation
Start with a SwiftUI-first native macOS shell that talks to the existing Python engine through a narrow backend API. Revisit a Swift rewrite only after the GUI shape and backend contract are proven.

## Current Implementation Checkpoint
Item 3 (settings / auth-repair UI) of the five-item live-slice orchestration in `docs/orchestration-plan.md` is the active checkpoint. PR #18 merged item 2 (task list filtering UI) into `feature/mac-prototype` on 2026-05-03 (squash merge `c29c630`); item 3 is now in the design phase on `codex/item-3-settings-auth-repair`. Scope: a SwiftUI `Settings` scene that diagnoses `gh` discovery and `auth.status` failures (the Finder-PATH risk recorded in `docs/handoff.md`) and helps users repair them; likely adds at least one new helper command (e.g. `auth.diagnose`) reporting discovered `gh` path/version/install state, gh-authentication state for the configured host, and the helper-resolved `PATH`, plus a matching `BackendClient` method, a workflow `SettingsModel` on `AgendumMacWorkflow`, and a `Settings { SettingsView() }` scene in `Sources/AgendumMac/AgendumMacApp.swift`. The design doc `docs/design/03-settings-auth-repair.md` is the immediate deliverable; the build phase begins after design review cycle 1 reports no findings. Packaging-decision routing remains deferred per `docs/packaging.md` and is not blocking item 3.

## Canonical Supporting Docs
- `docs/status.md`: current milestone, done/in-progress/blocked/next state, and milestone exit criteria.
- `docs/decisions.md`: append-only decision log. Record plan changes here before silently changing direction.
- `docs/handoff.md`: current repo state, validation, changed files, and exact next actions.
- `docs/mac-gui-port-evaluation.md`: architectural assessment and open product/distribution risks.
- `docs/backend-contract.md`: v0 backend bridge contract once drafted.
- `docs/testing.md`: testing strategy, milestone gates, and validation expectations.

## Milestones
1. Standalone scaffold: local SwiftUI app builds, planning docs are in this repo, and public `main` remains README-only.
2. Backend contract: define a versioned helper protocol for task loading, actions, sync, namespace, auth status, and errors. The accepted v0 bridge now has initial Swift client wiring.
3. Python service extraction: expose the required GUI commands from the existing agendum engine without importing Textual.
4. Live vertical slice: replace sample data with backend-loaded tasks, force sync, show sync status/errors, open task URLs, and mutate task status/remove.
5. Mac polish: add settings, menu coverage, keyboard shortcuts, notifications, state restoration, and packaging decisions.

## Testing Strategy
Testing should grow with each prototype risk rather than wait for the live slice.

- Backend helper changes require Python unit tests for command behavior, protocol validation, and stable error schemas.
- Helper process behavior requires subprocess JSONL integration tests against `Backend/agendum_backend_helper.py`.
- Swift helper-client code requires Swift tests for request/response encoding, model decoding, and error mapping before it is wired deeply into SwiftUI views.
- UI validation starts as documented manual smoke tests and should become automated once the live vertical slice stabilizes.
- Each milestone should update `docs/status.md` and `docs/handoff.md` with the exact validation commands and results.

The detailed testing plan lives in `docs/testing.md`.

## Prototype Acceptance Criteria
- `swift build` passes.
- Python backend unit and subprocess integration tests pass.
- Swift helper-client tests pass once a Swift client exists.
- `swift run AgendumMac` launches the app.
- The app can load tasks from the backend helper, not hard-coded sample data.
- The app can force sync and display sync progress or terminal errors.
- The app can open a GitHub URL and perform the core task actions currently available in the TUI.
- A fresh session can resume from `docs/handoff.md` without needing chat history.

## Backend Contract Requirements
The first GUI contract must cover:
- request/response envelope with protocol version, request id, command, payload, success/error fields
- task list/search/get
- manual task create
- task actions: mark reviewed, mark in progress, move to backlog, mark done, remove, mark seen
- sync actions: force sync, current sync status, progress/events or polling semantics, cancellation decision
- workspace actions: list/select/default namespace and load config
- auth actions: report `gh` presence/auth status and give repair instructions
- browser/link metadata, with URL opening owned by the Mac app
- stable error schema suitable for Swift UI presentation

For the prototype, prefer a JSON-over-stdio helper process. MCP can inform command shape, but it is assistant-facing and should not be treated as the Mac app contract unless a future decision says otherwise.

## Early Decision Gates
- Long-lived helper process versus one-shot command invocation.
- Whether Swift ever reads SQLite directly. Current bias: no; the helper owns DB access to avoid concurrency drift with the CLI.
- Development runner versus production runner: checked-out `../agendum`, installed `agendum`, bundled Python/backend, Homebrew dependency, or another path.
- Direct distribution versus Mac App Store.
- Auth UX: show status/repair instructions, launch Terminal, use `gh auth login --web`, or replace `gh` auth/API access later.

## Out Of Scope Until Later
- Menu bar-only product shape.
- Mac App Store readiness.
- Full Swift rewrite of the sync engine.
- Direct SQLite access from Swift.
- Notifications and state restoration before the live vertical slice works.
