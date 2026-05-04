# Orchestration Plan: Five Live-Slice Checkpoints

This plan governs an automated sequential delivery of five live-slice checkpoints into `feature/mac-prototype`. Packaging decisions remain deferred (see `docs/packaging.md`); these checkpoints are non-packaging.

## Items

Items run sequentially, one per PR, in this order. Order roughly tracks ascending complexity and minimizes cross-item conflicts.

1. **Open task URL action** (`codex/item-1-open-task-url`). Detail-pane action that opens a task's URL in the user's default browser. Scope: Swift (`AgendumMacWorkflow` + `AgendumMac` SwiftUI). Backend already returns the URL via `task.list` / `task.get`; no helper changes expected.
2. **Task list filtering UI** (`codex/item-2-task-list-filtering`). Surface the existing `task.list` filter parameters (status, project, source, includeSeen, limit) as sidebar/toolbar controls. Scope: Swift workflow + SwiftUI; backend already implements the filters.
3. **Settings / auth-repair UI** (`codex/item-3-settings-auth-repair`). First-run-friendly Settings scene that diagnoses and assists `gh` discovery and `auth.status` repair. Likely adds new helper command(s) (e.g. `auth.diagnose`, surfacing PATH/install state) plus a SwiftUI settings scene. Addresses the Finder-PATH risk in `docs/handoff.md`.
4. **Keyboard shortcuts + menu coverage** (`codex/item-4-shortcuts-menus`). Extend the menu (currently has `Sync Now`) with shortcuts for refresh, new task, and the per-task actions; ensure the focus model lets keyboard-only users drive the dashboard.
5. **Notifications + dock-badge for sync results** (`codex/item-5-notifications-badge`). Surface sync completion and the existing `hasAttentionItems` count via `UNUserNotificationCenter` and the macOS dock badge; introduces a new permissions surface (notification authorization).

## Per-Item Phase Machine

Each item progresses through six phases. Phase transitions are driven by agent-completion notifications back to the orchestrating session.

1. **design** — `crew:builder` authors `docs/design/<NN>-<slug>.md` with: goal, surface area, file-by-file change plan, test plan, risks, out-of-scope. Then `crew:reviewer` independently critiques the design (correctness, scope discipline, missing risks). Author revises until the reviewer reports no findings.
2. **build** — `crew:builder` implements per the approved design on the item's `codex/*` branch, includes the planning-doc roll-forward in the same commit set, opens a draft PR targeting `feature/mac-prototype`.
3. **review** — `crew:reviewer` performs a blind PR review (no chat history). If findings, dispatch `crew:builder` to address them as new commits. Loop until the reviewer reports no actionable findings at the project's standard confidence bar.
4. **validate** — `crew:validator` runs the project's full validation set (see "Validation Gates" below) and records evidence in `docs/handoff.md` under a new checkpoint block.
5. **ship** — Mark PR ready (if still draft); confirm CI green via `gh pr checks <N>`; merge with squash; fast-forward local `feature/mac-prototype`; prune local + remote branch.
6. **docs** — Roll forward `docs/status.md`, `docs/handoff.md`, `docs/plan.md`, and append to `docs/decisions.md` if any plan-affecting decision landed. These updates ride along inside the **next** item's PR (or, for item 5, in a small terminal docs PR that the user can choose to skip).

## Validation Gates

Per the existing project gates (see `docs/testing.md` + recent handoff entries):
- `swift build` passes.
- `swift test --enable-code-coverage` passes; expect new tests in `AgendumMacCoreTests` and/or `AgendumMacWorkflowTests` to grow the count.
- `/opt/homebrew/bin/python3 -m unittest discover -s Tests` passes.
- `/opt/homebrew/bin/python3 Scripts/python_coverage.py` passes; helper coverage stays ≥ 91%.
- `git diff --check` passes.
- `swift run AgendumMac` smoke-launches without immediate crash.
- For items that touch helper protocol surfaces, add or extend subprocess JSONL coverage in `Tests/test_backend_helper_process.py`.

## Branch and PR Discipline

- Each item lands via a PR from `codex/item-<N>-<slug>` → `feature/mac-prototype`. No item touches more than its own surface area; cross-cutting refactors are out of scope unless promoted to a dedicated checkpoint.
- After merge: fast-forward local `feature/mac-prototype`; the merged remote branch is auto-deleted by squash merge or pruned via `git fetch --prune`.
- Doc roll-forward never gets its own PR — it rides with the next item's PR (carrying the post-PR handoff state forward).

## Current State

- Anchor commit: `feature/mac-prototype` at `4172378` (post-PR-#21 squash merge tip).
- Active item: **none — orchestration complete**.
- Active branch: **none** (a short-lived `codex/post-orchestration-handoff` branch carries this docs PR but does not advance any item).
- Phase: **closed**.

## Progress Log

Append a one-line entry per phase transition with timestamp, item index, phase, and pointer (PR, commit, or doc).

- 2026-05-03: orchestration plan created on `codex/item-1-open-task-url`; planning docs rolled forward; item 1 design phase about to start.
- 2026-05-03: item 1 PR #17 (open task URL action) merged into `feature/mac-prototype` (squash merge `c2a6d97`); item 2 branch `codex/item-2-task-list-filtering` created from `c2a6d97`; item 2 design phase started with `docs/design/02-task-list-filtering.md`.
- 2026-05-03: item 2 PR #18 (task list filtering UI) merged into `feature/mac-prototype` (squash merge `c29c630`); item 3 branch `codex/item-3-settings-auth-repair` created from `c29c630`; item 3 design phase started with `docs/design/03-settings-auth-repair.md`.
- 2026-05-03: item 3 PR #19 (settings / auth-repair UI) merged into `feature/mac-prototype` (squash merge `c4a6b5a`); item 4 branch `codex/item-4-shortcuts-menus` created from `c4a6b5a`; item 4 design phase started.
- 2026-05-03: item 4 PR #20 (keyboard shortcuts + menu coverage) merged into `feature/mac-prototype` (squash merge `158954c`); item 5 branch `codex/item-5-notifications-badge` created from `158954c`; item 5 design phase started with `docs/design/05-notifications-badge.md`.
- 2026-05-03: item 5 PR #21 (notifications + dock badge for sync results) merged into feature/mac-prototype (squash merge 4172378); five-item orchestration COMPLETE. No further items in queue. Final test totals: 119 Swift / 61 Python / 92.4% backend coverage.
