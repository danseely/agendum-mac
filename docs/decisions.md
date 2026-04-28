# Decisions

## 2026-04-28
- Decision: Create a separate local `agendum-mac` project for GUI work.
- Reason: The GUI exploration should not churn the existing terminal CLI repo.
- Impact: Planning docs and Mac app scaffold live here; `../agendum` remains the backend/reference source.
- Plan change: yes; the earlier planning docs were moved out of `../agendum`.

## 2026-04-28
- Decision: Treat the first macOS effort as a native shell around the existing Python engine, pending prototype validation.
- Reason: The current agendum code already separates core task storage, sync, and GitHub status logic from the Textual UI enough to avoid an immediate rewrite.
- Impact: Early GUI work should focus on a backend contract and Mac-native UX rather than porting all domain logic to Swift.
- Plan change: no; this records the initial evaluation direction.

## 2026-04-28
- Decision: Use a Swift Package scaffold first, not a hand-authored Xcode project.
- Reason: It gives us a local SwiftUI app shell without brittle manual `.pbxproj` maintenance.
- Impact: A generated Xcode project or standard Xcode app template can be introduced once the prototype shape is clearer.
- Plan change: no.

## 2026-04-28
- Decision: Use a JSON-over-stdio helper process as the default bridge for the first live prototype.
- Reason: It keeps Swift and Python process-isolated, avoids direct Swift/Python embedding risk, and gives the Mac app a narrow contract it can own.
- Impact: The next planning artifact is `docs/backend-contract.md`; MCP remains assistant-facing/reference material unless a later decision changes this.
- Plan change: yes; this narrows the bridge choice before implementation.

## 2026-04-28
- Decision: Build a full windowed task dashboard before any menu bar helper.
- Reason: The existing product is a dashboard with grouped task triage, actions, sync status, and workspace context; the first Mac prototype should preserve that workflow.
- Impact: Menu bar behavior, notifications, and state restoration are deferred until the live windowed vertical slice works.
- Plan change: no.

## 2026-04-28
- Decision: The backend helper should own SQLite access for the prototype.
- Reason: The CLI and Mac app may run concurrently against the same workspace data, and keeping DB access behind one service boundary reduces concurrency and schema drift risk.
- Impact: Swift should call helper commands instead of reading or writing the SQLite database directly.
- Plan change: yes; this constrains the first backend design.

## 2026-04-28
- Decision: Accept `docs/backend-contract.md` for the first implementation pass.
- Reason: A fresh independent review found the revised contract clean after adding sync semantics, concrete schemas, URL metadata, workspace defaults, auth/PATH behavior, and helper-owned SQLite rules.
- Impact: Implementation can begin with the backend helper target/adapter using the accepted v0 JSON-over-stdio contract.
- Plan change: no.

## 2026-04-28
- Decision: Use stacked branches for the public prototype workflow.
- Reason: README-only `main` should stay minimal until the prototype is ready, while implementation checkpoints need reviewable branches that do not all target `main` directly.
- Impact: `feature/mac-prototype` is the broad integration branch off `main`; narrower branches such as `feature/backend-helper` target it.
- Plan change: yes; this replaces direct implementation PRs against `main` with a stacked PR workflow.
