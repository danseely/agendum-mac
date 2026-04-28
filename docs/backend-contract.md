# Backend Contract

Status: accepted for first implementation pass.

## Goal
Define the protocol that the native Mac app uses to talk to the agendum Python engine. This contract is intentionally narrow: Swift owns Mac UI and presentation; the helper owns agendum data, sync, auth state detection, and workspace config.

## Bridge Choice
Use a long-lived JSON-over-stdio helper process for v0.

Rationale:
- A long-lived process can own workspace state, sync status, and SQLite access.
- JSON-over-stdio avoids direct Swift/Python embedding and keeps crash boundaries clear.
- MCP can inform naming and data shape, but it is assistant-facing and not the Mac app contract unless a future decision in `docs/decisions.md` changes that.

## Framing
- Encoding: UTF-8 JSON Lines, one JSON object per line.
- Request/response: every request receives one response with the same `id`.
- Events: the helper may emit event envelopes for sync state changes.
- Cancellation: no v0 cancellation command. A running sync is allowed to complete; duplicate `sync.force` requests should return the current sync state rather than starting another sync.
- SQLite: Swift does not read or write SQLite directly.
- URL opening: the Mac app opens URLs. The helper returns canonical URLs in task payloads.

## Request Envelope

```json
{
  "version": 1,
  "id": "req-001",
  "command": "task.list",
  "payload": {}
}
```

Fields:
- `version`: integer, currently `1`
- `id`: caller-generated string, echoed in the response
- `command`: command name
- `payload`: command-specific object, empty when unused

## Success Response Envelope

```json
{
  "version": 1,
  "id": "req-001",
  "ok": true,
  "payload": {}
}
```

## Error Response Envelope

```json
{
  "version": 1,
  "id": "req-001",
  "ok": false,
  "error": {
    "code": "auth.missing",
    "message": "GitHub authentication is not available.",
    "detail": "gh auth status failed for the selected workspace.",
    "recovery": "Open Settings and repair GitHub authentication."
  }
}
```

Error fields:
- `code`: stable machine-readable string
- `message`: user-presentable summary
- `detail`: optional technical detail
- `recovery`: optional user-presentable next step

Common error codes:
- `protocol.unsupportedVersion`
- `protocol.unknownCommand`
- `payload.invalid`
- `task.notFound`
- `workspace.invalid`
- `auth.ghNotFound`
- `auth.missing`
- `auth.expired`
- `sync.inProgress`
- `sync.failed`
- `storage.failed`

## Event Envelope

```json
{
  "version": 1,
  "event": "sync.statusChanged",
  "payload": {
    "state": "running",
    "message": "Syncing GitHub tasks"
  }
}
```

Events are advisory. The Mac app may also poll `sync.status`.

## Shared Types

### Task

```json
{
  "id": 42,
  "title": "Add review-thread resolution tracking",
  "source": "pr_authored",
  "status": "review received",
  "project": "agendum",
  "ghRepo": "danseely/agendum",
  "ghUrl": "https://github.com/danseely/agendum/pull/42",
  "ghNumber": 42,
  "ghAuthor": "octocat",
  "ghAuthorName": "Octo",
  "tags": ["review"],
  "seen": false,
  "lastChangedAt": "2026-04-28T15:00:00+00:00",
  "updatedAt": "2026-04-28T15:01:00+00:00"
}
```

Notes:
- Field names use lower camel case over the bridge.
- `ghUrl` is the canonical browser URL. The Mac app owns opening it.
- `source` values mirror agendum: `pr_authored`, `pr_review`, `issue`, `manual`.
- `status` values mirror agendum's existing statuses for v0.

### Workspace

```json
{
  "id": "base",
  "namespace": null,
  "displayName": "Base Workspace",
  "configPath": "~/.agendum/config.toml",
  "dbPath": "~/.agendum/agendum.db",
  "isCurrent": true
}
```

Workspace semantics:
- The default/base workspace has `id: "base"` and `namespace: null`.
- Namespace workspaces map to existing agendum workspace paths under `~/.agendum/workspaces/<namespace>`.
- Selecting a workspace loads or creates its config using the existing agendum config rules.

### Sync Status

```json
{
  "state": "idle",
  "lastSyncAt": "2026-04-28T15:01:00+00:00",
  "lastError": null,
  "changes": 3,
  "hasAttentionItems": true
}
```

`state` values:
- `idle`
- `running`
- `suspended`
- `error`

### Auth Status

```json
{
  "ghFound": true,
  "ghPath": "/opt/homebrew/bin/gh",
  "authenticated": true,
  "username": "danseely",
  "workspaceGhConfigDir": "~/.agendum/gh",
  "repairInstructions": null
}
```

Auth semantics:
- The helper must search explicit common `gh` paths rather than relying only on Finder-launched app `PATH`.
- If `gh` is missing, return `ghFound: false` and repair instructions.
- If auth is missing or expired, return `authenticated: false` and repair instructions.
- v0 does not perform interactive auth itself.

## Commands

### `task.list`
Request:
```json
{
  "source": "pr_review",
  "status": "review requested",
  "project": "agendum",
  "includeSeen": true,
  "limit": 50
}
```
All filters are optional. Response:
```json
{ "tasks": [] }
```

### `task.search`
Request:
```json
{
  "query": "review api",
  "source": null,
  "status": null,
  "project": null,
  "limit": 20
}
```
Response:
```json
{ "tasks": [] }
```

### `task.get`
Request:
```json
{ "id": 42 }
```
Response:
```json
{ "task": null }
```

### `task.createManual`
Request:
```json
{
  "title": "Sketch Mac backend contract",
  "project": "agendum-mac",
  "tags": ["planning"]
}
```
Response:
```json
{ "task": {} }
```

### Task Action Commands
Commands:
- `task.markReviewed`
- `task.markInProgress`
- `task.moveToBacklog`
- `task.markDone`
- `task.remove`
- `task.markSeen`

Request:
```json
{ "id": 42 }
```

Response:
```json
{ "task": {} }
```

For `task.remove`, response may use:
```json
{ "removed": true }
```

### `sync.force`
Request:
```json
{}
```
Response:
```json
{ "status": {} }
```

Semantics:
- If no sync is running, start one and return `state: "running"`.
- If a sync is already running, return current status without starting a second sync.
- Completion should be observable through `sync.status` polling and optional `sync.statusChanged` events.

### `sync.status`
Request:
```json
{}
```
Response:
```json
{ "status": {} }
```

### `workspace.current`
Request:
```json
{}
```
Response:
```json
{ "workspace": {} }
```

### `workspace.list`
Request:
```json
{}
```
Response:
```json
{ "workspaces": [] }
```

Must include the default/base workspace even if no namespace workspaces exist.

### `workspace.select`
Request:
```json
{
  "namespace": "example-org"
}
```

Use `namespace: null` to select the default/base workspace.

Response:
```json
{
  "workspace": {},
  "auth": {},
  "sync": {}
}
```

Semantics:
- Loads or creates workspace config using existing agendum rules.
- Sets the helper's current workspace.
- Does not automatically run sync unless a later implementation decision adds that behavior.

### `auth.status`
Request:
```json
{}
```
Response:
```json
{ "auth": {} }
```

## Ownership Rules
- The helper owns SQLite reads and writes.
- The helper owns GitHub sync, task status derivation, auth state detection, and workspace config loading.
- The Mac app owns windows, menus, settings UI, browser opening, and user-facing presentation.
- Swift does not read or write `~/.agendum` SQLite files directly in the prototype.

## Acceptance Criteria
- A fresh session can implement the helper and Swift client from this file plus `docs/plan.md`.
- The contract covers the first live vertical slice described in `docs/mac-gui-port-evaluation.md`.
- Any missing command is recorded here before implementation starts.
