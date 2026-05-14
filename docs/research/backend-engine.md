# Research: Standalone Backend Engine

> Stream A of the 2026-05-03 architecture-direction research. Captured verbatim from the `crew:researcher` run that produced it; cited claims should be re-verified before they harden into commitments. Companion docs: `docs/research/data-store.md`, `docs/research/architecture.md`, `docs/research/synthesis.md`.

## Decision context

The user has decided that `agendum-mac` should be a fully standalone product with **no Python at runtime** and no sibling-checkout dependency on `../agendum`. This stream evaluates how to get there. The stronger directive ("rip Python out") was made after this report was written; the recommended path below remains the right starting sequence — fork-and-vendor first, then incremental Swift port — with the difference that the terminal state is now non-negotiable: Python goes to zero.

## Executive Summary

The Python engine `agendum-mac` depends on (`/Users/dseely/dev/agendum`) is roughly **3,300 LOC of non-trivial logic** across `gh.py` (1,546), `syncer.py` (1,056), `config.py` (213), `db.py` (197), `task_api.py` (175), and `gh_review.py` (147). The riskiest, highest-value piece is `gh.py` + `syncer.py` together: a multi-stage GraphQL discovery → hydration → verification → diff pipeline with subtle terminal-state suppression rules and review-attention heuristics. The helper protocol the Mac app depends on (`Backend/agendum_backend/helper.py`, ~710 LOC) is narrow (13 commands) and stable. Five real options exist; in 2025-2026 the realistic choices collapse to (a) **vendor + bundle Python via Briefcase or PyInstaller** (fastest path, preserves the v0 contract, hardest packaging story), or (d) **incremental Swift port behind the v0 helper boundary** (longer, but ends with one shippable artifact, no Python at runtime, and a clean MAS path later). Recommendation: **pick (b/c) — fork-and-vendor the Python engine into this repo today, then incrementally port it to Swift behind the unchanged v0 contract** — the smallest first commit-bearing slice is moving `agendum/src/agendum/` into `agendum-mac/Backend/agendum_engine/` and pointing CI at it.

## 1. Engine Scope

The Mac app today reaches the Python world only through 13 helper commands defined in `/Users/dseely/dev/agendum-mac/Backend/agendum_backend/helper.py` (lines 116-141): `workspace.{current,list,select}`, `auth.{status,diagnose}`, `task.{list,get,createManual,markReviewed,markInProgress,moveToBacklog,markDone,markSeen,remove}`, and `sync.{status,force}`. That helper is a thin wrapper; everything load-bearing lives in the sibling Python tree.

Concrete engine pieces and their irreducibility:

- **Data model + persistence (`db.py`, 197 LOC).** Single `tasks` table with 16 columns, two pragmas (WAL + busy_timeout), one column-add migration (`gh_node_id`), one data migration (`active`→`backlog`), four indexes, and a small CRUD surface (`add_task`, `get_active_tasks`, `update_task`, `remove_task`, `find_task_by_gh_url`, `find_tasks_by_gh_node_ids`, `mark_all_seen`). Trivial to port. The on-disk file at `~/.agendum/agendum.db` (or `~/.agendum/workspaces/<owner>/agendum.db`) is the user's data and must be preserved across any backend swap.

- **Config + workspace paths (`config.py`, 213 LOC).** TOML loader (uses 3.11 stdlib `tomllib`), `RuntimePaths` dataclass, namespace normalization (a GitHub-owner regex), default-config writer with 0o700/0o600 perm hardening. Trivial to port; the namespace rules are deliberately strict.

- **GitHub integration (`gh.py`, 1,546 LOC).** This is the hard core. It is **not** a thin wrapper around `gh` — it is a GraphQL query authoring + paging + completeness-tracking layer that *invokes* the `gh` CLI as the transport (see `_run_gh` lines 209-225, plus `gh api graphql` calls throughout). Concretely:
  - Pure status derivation (`derive_authored_pr_status`, `derive_review_pr_status`, `derive_issue_status`, `has_unacknowledged_review_feedback`, ~165 LOC). Pure functions, easy to port and test against fixtures.
  - GraphQL query builders for authored PRs, assigned issues, review-requested PRs, repo archive states, PR/issue/review hydration, and missing-item verification. Multiple batched queries (`_HYDRATE_BATCH_SIZE=50`, `_VERIFY_BATCH_SIZE=50`, repo chunk size 10).
  - Subprocess-based auth-state detection, `GH_CONFIG_DIR` workspace-isolation contextvar, multi-source auth recovery (`recover_gh_auth`, `seed_gh_config_dir`, `refresh_gh_config_dir`).
  - Notifications via REST (`fetch_notifications`).
  - Completeness tracking on every fetch (each `*_with_completeness` fn returns `(items, ok)`), feeding the suppression logic in `syncer.py`.

- **Sync algorithm (`syncer.py`, 1,056 LOC).** A planner-style state machine: `OpenDiscoveryCoverage` → `OpenHydrationBundle` → `MissingVerificationRequest` → `MissingVerificationBundle` → `CloseSuppression` → `SyncPlan` → `diff_tasks` → `_apply_sync_diff` → `_apply_notifications`. The non-obvious rules: per-lane close suppression on partial fetch, repo-archive filtering, scoped-org backfill for "dormant in-scope" repos, `pr_review` exemption from `fetched_repos` because GitHub drops repos from `--review-requested` once the user is removed (see `_task_is_verifiable_in_planner_scope`, lines 738-749). Attention classification flags `review_received`, `re-review requested`, `changes requested`, `approved`, plus notification-driven re-unseen. **This is the single biggest porting risk**; the rules are encoded as imperative code with no formal spec.

- **Manual task creation, status transitions, mark-seen, remove** (in `task_api.py` and `db.py`). Trivial: ~30 LOC of real work behind any of the 8 task action commands.

**Irreducible engine** for `agendum-mac` to stay functional: SQLite store + workspace/config + the GraphQL→diff sync loop + GitHub auth/transport. Everything the Mac app calls today bottoms out into one of those four. Approximate split: **trivial-port ~600 LOC (db, config, task_api, status derivation), hard-port ~2,600 LOC (gh.py transport+queries+auth, syncer planner)**.

## 2. Options for "Standalone"

### (a) Vendor Python source + bundle a Python runtime

**How:** Move (or git-subtree) `../agendum/src/agendum/` into `agendum-mac/Backend/agendum_engine/`, update the helper's `_bootstrap_agendum_import()` (helper.py lines 24-31) to import the in-tree copy, and ship a frozen interpreter inside `Agendum.app/Contents/Resources/`. Two realistic freezers: **Briefcase** (BeeWare; uses `Python-Apple-support`, designed for App Store submission today, [briefcase docs](https://briefcase.beeware.org/en/stable/reference/platforms/macOS/)) and **PyInstaller** (more mature, less app-store-friendly, [stupidtech.io 2025 walkthrough](https://stupidtech.io/2025/03/15/how-to-make-a-python-script-into-a-macos-app-with-py2app-code-sign-notarize/)). py2app is on the menu but feels like a maintenance laggard.

**Gain:** v0 helper protocol unchanged. Existing test surface preserved. ~2 weeks of work. Sibling-checkout discipline disappears.

**Lose:** The packaging story is the worst part of the project for the lifetime of the app — every Python upgrade, every Apple notarization rule change ([CPython issue #120522](https://github.com/python/cpython/issues/120522): Python 3.12 was auto-rejected from MAS for embedding the string `itms-services`), every nested-signing change, every privacy manifest change cuts you. Library Validation must be disabled for embedded interpreters ([dev.to write-up](https://dev.to/eldare/embedding-python-interpreter-inside-a-macos-app-and-publish-to-the-app-store-successfully-4bop)), which complicates MAS and hardens-runtime stories. App size grows by ~20-40 MB. CI matrix grows.

**Maintenance shape:** Re-freeze on every Python point release. Track Apple notarization rule changes separately from the rest of macOS dev. Two languages forever.

### (b) Fork-and-vendor as a frozen point-in-time snapshot, still Python

Same as (a) but **explicitly forks** the engine; `agendum-mac` owns it going forward, `../agendum` becomes irrelevant. No runtime decision yet — defer (a)'s freezer pick.

**Gain:** Cuts the sibling-checkout dependency immediately. Buys time. Keeps the door open for either keeping Python or progressively porting to Swift module-by-module behind the v0 helper. CI simplifies (no two-repo checkout).

**Lose:** TUI parity with the upstream `agendum` drifts; if the user wants a single product across Mac+terminal, they now have two engines to keep in sync. But the user has explicitly chosen Mac-standalone, so this loss is a feature.

**Maintenance shape:** Vendored copy ages; you accept that. Best when paired with (c).

### (c) Partial Swift port behind the v0 helper boundary

Keep (b)'s vendored Python initially. Then port one engine module at a time into Swift, **keeping the v0 helper as a façade** that internally dispatches to either Python or Swift. Natural slice order: `db.py` → `config.py` → `task_api.py` → status-derivation pure functions → `gh.py` GraphQL transport → `syncer.py` planner.

**Gain:** Each slice is reviewable and reversible. The Mac app's `BackendClient` never changes. Eventually the Python pieces evaporate and the helper becomes a Swift in-process module (or stays a subprocess for crash isolation).

**Lose:** Two implementations coexist for months. Test surface doubles in the middle of the migration. Discipline-heavy.

**Maintenance shape:** Bounded migration, ends with zero Python. Best long-term.

### (d) Full Swift rewrite of the engine, immediate

**How:** Native SQLite via `GRDB.swift`. Native GitHub via `URLSession`+a small GraphQL client (or `Octokit.swift` for REST plus hand-rolled GraphQL — see [octokit.swift](https://github.com/nerdishbynature/octokit.swift)). Native auth via `AppAuth-iOS` device flow ([AppAuth-iOS](https://github.com/openid/AppAuth-iOS)) or `OAuth2DeviceGrant` ([p2/OAuth2](https://github.com/p2/OAuth2)). Replace the helper subprocess entirely.

**Gain:** Single-language codebase. Mac App Store viable. Sandbox-clean. No nested-signing nightmare. Smaller app. Better startup and memory profile.

**Lose:** ~2,600 LOC of subtle GraphQL+sync logic must be re-encoded with no formal spec. The `agendum` test suite (in `../agendum`) does not transfer. Time-to-feature stalls for weeks-to-months. High risk of behavior drift in the attention classifier and close-suppression rules — the very behaviors that make the product useful.

**Maintenance shape:** Best after the first ship. Worst before it.

### (e) Other paths considered

- **Rust core via FFI.** Rewrites the same subtle logic into a different new language and adds an FFI boundary. Strictly worse than (d) for this product.
- **System `python3` + pip-installed `agendum`.** Works for power users only. Ties version floor to whatever Apple ships and forces a `pip install` on first run. Already evaluated and rejected in `docs/packaging.md`.
- **Cloud service.** Would solve packaging but introduces auth-server hosting, a new threat model for users' GitHub data, and latency on every action. Not aligned with the product.

## 3. Coupling & Migration

**Helper protocol preservation:** Options (a), (b), (c) all preserve the v0 contract verbatim — the `BackendClient` in Swift is untouched. (d) requires either keeping the v0 contract over an in-process or XPC boundary (recommended even if the implementation is Swift, because it preserves the well-tested boundary and lets you crash-isolate sync) or redesigning the contract. The lazy and correct answer for (d) is to keep v0 as a Swift-in-Swift API surface.

**On-disk SQLite compatibility:** All options can preserve `~/.agendum/agendum.db`. The schema in `db.py` lines 8-28 is small and well-defined; a Swift `GRDB` port would target the same schema. The one nuance is `~/.agendum` vs `~/Library/Application Support/agendum/` — already an open decision in `docs/packaging.md` #7. MAS sandboxing forces the latter; non-MAS distribution can keep the former.

**Smallest first slice that proves direction:**
1. `git mv ../agendum/src/agendum agendum-mac/Backend/agendum_engine` (or git-subtree merge to preserve history).
2. Update `helper.py` lines 24-31 `_bootstrap_agendum_import()` to import the in-tree copy unconditionally.
3. Update `.github/workflows/test.yml` to drop the sibling checkout.
4. Update `Scripts/python_coverage.py` and the helper tests' import paths.

That's a one-PR slice that immediately delivers "no sibling-checkout requirement" — the user's stated goal — without touching any runtime or rewrite question. It is the cheapest move that proves direction (b), and it is also strictly required as step 1 of (a) or (c).

## 4. Apple / App Store Implications (2025-2026)

Sources: [Briefcase macOS docs](https://briefcase.beeware.org/en/stable/reference/platforms/macOS/), [Apple developer forum thread on Python embedding](https://developer.apple.com/forums/thread/766290), [Glyph 2023 write-up](https://blog.glyph.im/2023/03/py-mac-app-for-real.html) (still the best end-to-end account), [Michael Tsai's roundup](https://mjtsai.com/blog/2024/06/28/python-apps-rejected-from-app-store/), [CPython #120522](https://github.com/python/cpython/issues/120522).

**Bundling Python in 2025-2026:**
- The dominant idiomatic path is **Briefcase + Python-Apple-support** ([beeware/Python-Apple-support](https://github.com/beeware/Python-Apple-support)). Briefcase is the only Python toolchain that explicitly targets Mac App Store submission via an Xcode project format and is actively maintained (Briefcase 0.3.25 shipped Nov 2025).
- **PyInstaller** still works for Direct distribution and is more battle-tested for sign-and-notarize, but it is not designed for MAS and the `--deep` codesign flag developers used to rely on is deprecated; signing must now be bottom-up.
- **py2app** is technically alive but maintenance signal is low.
- **`python-build-standalone`** (Indygreg, now under Astral) is the runtime most modern tools use under the hood; you can use it directly with a hand-rolled signing pipeline, but you will be reinventing what Briefcase already did.

**Notarization gotchas for any Python bundle:** hardened runtime requires `com.apple.security.cs.allow-unsigned-executable-memory` (Python's interpreter writes JIT-like memory). Library Validation must be disabled (`com.apple.security.cs.disable-library-validation`) so the embedded `.so` files load — which is a strong signal against MAS and complicates the trust story for direct distribution. Every nested `.so` and `.dylib` in the bundle must be individually signed before the parent. The 2024 `itms-services` rejection ([CPython #120522](https://github.com/python/cpython/issues/120522)) is a concrete example of how Apple's automated review can break embedded Python on a Python point upgrade — Briefcase patches CPython to mitigate; raw PyInstaller does not.

**Per-option MAS eligibility:**
- (a) Vendor + freeze: **MAS hostile**. Possible with Briefcase + extensive entitlements; one auto-rejection per CPython upgrade is realistic.
- (b) Vendor source only, no runtime change: same as (a) once a runtime is added; deferred MAS decision.
- (c) Partial Swift port: same as (a)/(b) until Python is gone; **MAS-friendly** at the end.
- (d) Full Swift: **MAS-friendly day one**, sandbox-clean, no entitlement gymnastics.

**Direct distribution (Developer ID + notarytool):** all options work. The cost difference is operational, not yes/no.

## 5. GitHub Auth Implications

Today: `helper.py` lines 412-456 + `gh.py` `auth_status`/`get_gh_username`/`use_gh_config_dir` shell out to user-installed `gh` with `GH_CONFIG_DIR=~/.agendum/.../gh`.

- (a)/(b) **Keep `gh`.** Direct distribution: works as-is. MAS/sandbox: blocked — sandboxed apps can't reliably spawn `/opt/homebrew/bin/gh` and can't read `~/.config/gh`. A MAS-eligible build under (a)/(b) would have to ship `gh` as an embedded binary too, which is yet another nested-signing artifact.
- (c) **Replace `gh` mid-migration or at the end.** When the GraphQL transport moves to Swift, replace it with a native OAuth Device Flow + token-keychain stored client. The v0 `auth.status` and `auth.diagnose` payloads continue to work; `repairCommand` becomes "open Settings → Sign in with GitHub" instead of a shell command.
- (d) **Replace `gh` immediately.** Use [AppAuth-iOS](https://github.com/openid/AppAuth-iOS) or [p2/OAuth2's `OAuth2DeviceGrant`](https://github.com/p2/OAuth2) for Device Flow (works headlessly, no embedded webview). Store the token in Keychain. This is the only option that is MAS-clean from day one. Octokit.swift handles REST; for GraphQL the transport is just `URLSession` + `application/json`.

The user's existing decision to keep `gh` (`docs/plan.md` Constraints, line 19) is the binding constraint for (a)-(c) on Direct distribution. It will not survive any move toward MAS.

## 6. Recommendation

**Recommended path: (b) → (c) — fork-and-vendor the Python engine into this repo now, then incrementally Swift-port behind the unchanged v0 helper boundary.**

Rationale:
- The user's explicit goal is "no sibling-checkout requirement, no Python dependency contract on `../agendum`." (b) achieves that in a single PR with zero behavior change.
- It does not commit to a packaging story before the user has answered the deferred decisions in `docs/packaging.md`.
- It does not commit to a Swift rewrite before the user has felt the migration cost on a small slice.
- The v0 helper protocol is the asset to protect — it is the well-tested narrow waist between Swift and engine. Both (a) and (c) keep it intact; (d) discards a real test asset for no near-term win.
- It keeps `~/.agendum/agendum.db` compatibility free (no migration in slice 1).
- It is reversible. If the user later decides to ship via Briefcase, the vendored tree is exactly what Briefcase consumes. If the user later decides on full Swift, the vendored tree becomes the spec for the port.

**Smallest first commit-bearing slice (de-risks the direction):**
1. Create `agendum-mac/Backend/agendum_engine/` and copy `../agendum/src/agendum/` into it (prefer `git subtree add` to preserve history; acceptable to do a flat copy if subtree feels heavy).
2. Replace the runtime `_bootstrap_agendum_import()` in `Backend/agendum_backend/helper.py` (lines 24-31) with an unconditional import of the new in-tree package.
3. Update `Tests/test_backend_helper*.py` import paths and `Scripts/python_coverage.py` to point at the in-tree copy.
4. Update `.github/workflows/test.yml` to drop the sibling-`agendum` checkout step.
5. Add a `docs/decisions.md` entry recording: "Forked the agendum engine into `agendum-mac/Backend/agendum_engine/`. Sibling-checkout discipline retired. Engine evolution now happens here."

That slice ships in one PR, breaks no Mac UI behavior, removes the user's stated coupling pain, and unlocks every downstream option.

**Ranked fallback options:**
1. **(c) Incremental Swift port.** After (b) is in, the next slice is moving the pure status-derivation functions in `gh.py` (lines 40-202) to Swift — they are pure, well-bounded, and have existing Python tests to port as fixtures.
2. **(a) Briefcase-bundled Python.** If the user wants direct distribution today and is willing to accept MAS risk and the one-rejection-per-CPython-upgrade tax. Pick Briefcase over PyInstaller because of MAS optionality and active 2025 maintenance ([Briefcase 0.3.25, Nov 2025](https://briefcase.beeware.org/_/downloads/en/v0.3.25/pdf/)).
3. **(d) Full Swift rewrite.** Only if the user accepts a multi-month feature freeze. Highest behavior-drift risk in the attention classifier and close-suppression rules.
4. **System Python / Homebrew prerequisite.** Lowest engineering effort but breaks the "self-contained Mac app" goal the user just stated. Strictly worse than (b).

**Key files referenced (absolute paths):**
- `/Users/dseely/dev/agendum-mac/Backend/agendum_backend/helper.py` (helper, 710 LOC, the contract surface)
- `/Users/dseely/dev/agendum-mac/docs/plan.md`, `docs/backend-contract.md`, `docs/packaging.md`, `docs/decisions.md` (existing planning context)
- `/Users/dseely/dev/agendum/src/agendum/db.py` (197 LOC; trivial port)
- `/Users/dseely/dev/agendum/src/agendum/config.py` (213 LOC; trivial port)
- `/Users/dseely/dev/agendum/src/agendum/task_api.py` (175 LOC; trivial port)
- `/Users/dseely/dev/agendum/src/agendum/syncer.py` (1,056 LOC; hard port — the planner)
- `/Users/dseely/dev/agendum/src/agendum/gh.py` (1,546 LOC; hardest port — GraphQL+auth)
- `/Users/dseely/dev/agendum/src/agendum/gh_review.py` (147 LOC)

**Sources for Apple/Python claims:**
- Briefcase macOS reference: https://briefcase.beeware.org/en/stable/reference/platforms/macOS/
- Python-Apple-support meta-package: https://github.com/beeware/Python-Apple-support
- CPython App Store auto-rejection (3.12 `itms-services`): https://github.com/python/cpython/issues/120522
- Michael Tsai roundup of 2024 Python MAS rejections: https://mjtsai.com/blog/2024/06/28/python-apps-rejected-from-app-store/
- Glyph: Building a macOS app written in Python (still the best end-to-end account): https://blog.glyph.im/2023/03/py-mac-app-for-real.html
- 2025 py2app sign+notarize walkthrough: https://stupidtech.io/2025/03/15/how-to-make-a-python-script-into-a-macos-app-with-py2app-code-sign-notarize/
- Apple Developer Forums on Python interpreter embedding: https://developer.apple.com/forums/thread/766290
- Octokit.swift: https://github.com/nerdishbynature/octokit.swift
- AppAuth-iOS (device flow on macOS): https://github.com/openid/AppAuth-iOS
- p2/OAuth2 with `OAuth2DeviceGrant`: https://github.com/p2/OAuth2
