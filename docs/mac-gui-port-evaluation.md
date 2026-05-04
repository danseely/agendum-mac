# macOS GUI Port Evaluation

## Summary
Porting agendum to a proper Mac GUI is feasible. The current app is a Textual terminal shell over a more reusable Python engine: SQLite storage, config/workspace paths, GitHub sync, task querying, and MCP tools are already mostly outside the TUI.

The lowest-risk path is a native SwiftUI macOS app that talks to the existing Python engine through a narrow backend contract. A full Swift rewrite is possible later, but it would front-load risk in GitHub GraphQL behavior, sync edge cases, workspace auth handling, and release automation.

## Current App Shape
- Product: local dashboard for GitHub PRs, review requests, assigned issues, and manual tasks.
- UI: Textual table with sections, keyboard navigation, action modal, namespace switching, sync status, and manual task creation.
- Data: SQLite database under `~/.agendum`, with per-namespace workspaces under `~/.agendum/workspaces/<owner>`.
- GitHub integration: `gh` subprocess calls, including `gh search`, `gh api graphql`, notifications, and isolated workspace `GH_CONFIG_DIR` handling.
- Automation surface: `task_api.py` exposes list/search/get/create; `mcp_server.py` exposes a subset of task and PR-review functionality.

## Reusable Pieces
- `db.py`: usable local task store, schema, update operations, and seen tracking.
- `config.py`: workspace and namespace path model.
- `syncer.py`: async sync orchestration and diffing.
- `gh.py`: GitHub queries, status derivation, auth recovery, and `gh` subprocess wrapper.
- `task_api.py`: GUI-ready read/search/create foundation, but needs action/update coverage.
- `mcp_server.py`: useful proof that the backend can be driven outside the TUI.

## Current Coupling
- `app.py` owns timers, focus tracking, sync lifecycle, action handling, browser opening, seen timing, and namespace switching in one UI class.
- `widgets.py` mixes display grouping and status colors with Textual/Rich types.
- The backend lacks a single app-service layer for commands like sync-now, mark-reviewed, mark-done, open URL metadata, switch namespace, and mark-seen.
- GitHub auth is CLI-oriented and interactive in terminal terms, not Mac app terms.

## Recommended Architecture
Use a SwiftUI-first macOS app with targeted AppKit where needed.

Native app responsibilities:
- Windows, sidebar/list/detail layout, toolbar, menus, settings, keyboard shortcuts, notifications, and app lifecycle.
- Settings UI for orgs/repos/exclusions, sync interval, seen delay, workspace selection, and auth status.
- Presentation of task sections and actions.
- Process lifecycle for the backend helper.

Python engine responsibilities:
- SQLite schema and migrations.
- GitHub sync and status derivation.
- Task mutation/query API.
- Existing CLI and MCP compatibility.

Bridge:
- Use a JSON-over-stdio backend helper as the first prototype default.
- MCP can inform the shape, but it is assistant-facing and not the app contract unless a later decision changes this.
- Avoid binding Swift directly to internal Python modules at first; process isolation keeps packaging and crash behavior simpler.
- Decide early whether the helper is long-lived or one-shot, how sync progress is reported, whether cancellation exists, and how protocol/error versions are represented.
- Keep SQLite access behind the helper for the prototype; Swift should not read or write the database directly.

## Prototype Target
Build a native windowed productivity app, not a menu bar utility first.

Minimum useful GUI:
- Sidebar or segmented filter for sections: My Pull Requests, Reviews Requested, Issues & Manual.
- Task list with status, title, author, repo, unread/new marker, and link number.
- Detail/action area for open in browser, mark reviewed, mark in progress, move to backlog, mark done, remove.
- Toolbar sync button and visible sync status.
- Settings window on `Cmd-,`.
- Workspace/namespace switcher.

Menu bar helper can come later if unread review requests become the main value proposition.

First live vertical slice:
- choose or default the workspace
- load tasks from the backend helper
- force sync and display sync status/errors
- open task URL in the browser
- mark reviewed, mark in progress, move to backlog, mark done, remove, and mark seen

Settings, notifications, state restoration, and menu bar behavior follow after this slice.

## Migration Steps
1. Extract an app-service layer in Python that wraps DB, config, sync, namespace, and task actions without importing Textual.
2. Expand tests around that service layer using the existing SQLite fixtures and sync tests.
3. Add subprocess JSONL tests around the backend command runner executable before relying on it from Swift.
4. Create an Xcode macOS app from the standard template or a project generator once the prototype shape is clear.
5. Implement a local-data prototype using seeded/demo data before live GitHub sync.
6. Connect the Swift app to the backend helper, with Swift helper-client tests for request/response decoding and error mapping.
7. Add Mac-native settings, menus, keyboard navigation, notifications, and state restoration.
8. Decide distribution channel, then harden signing, notarization, sandboxing, and packaging.

## Distribution Notes
Direct distribution is the simpler initial path because agendum currently depends on `gh` and local auth/config files. A Mac App Store build would require deeper sandbox design and may force replacing or embedding more GitHub auth/API behavior instead of shelling out to a user-installed `gh`.

Before release planning, re-check current Apple signing, notarization, privacy manifest, and sandbox requirements.

Packaging/runtime choices still need a decision:
- invoke a checked-out `../agendum` backend during development only
- depend on an installed `agendum`
- depend on Homebrew
- bundle Python plus the backend
- replace the Python/GitHub layer later

Finder-launched apps do not inherit a user's shell `PATH`, so `gh` discovery must be explicit.

## Open Questions
- Should the Mac app require `gh` to be installed, or bundle/replace GitHub API access?
- How should the Mac app repair missing or expired `gh` auth: show instructions, launch Terminal, run `gh auth login --web`, or replace `gh` auth later?
- Should the backend continue using `~/.agendum`, or migrate to `Application Support/agendum` with compatibility import?
- Is the primary Mac experience a full task dashboard, a lightweight menu bar triage tool, or both?
- Should direct distribution be the first target?
- How much of MCP should become the canonical backend contract versus a separate assistant-facing API?
