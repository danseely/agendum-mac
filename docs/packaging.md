# Packaging Matrix

## Overview
This document is a planning artifact, not an executable plan. The prototype phase has not chosen a macOS distribution channel for `agendum-mac` and has not chosen a production runtime strategy for the Python backend helper. It enumerates the options on both axes, captures their trade-offs against prior decisions in `docs/decisions.md`, and records a recommended posture for the prototype phase. A code-bearing packaging slice (for example `Scripts/build_app_bundle.sh` producing an unsigned `.app`) should not begin until the user has chosen a distribution channel and a Python runtime strategy from the menus below.

## Distribution channels matrix

| Channel | Signing | Notarization | `gh` compatibility | Sandbox | Prototype fit |
| --- | --- | --- | --- | --- | --- |
| Direct distribution (DMG / zip) | Developer ID Application | Yes | Works as-is (calls user-installed `gh`) | n/a | Immediate; smallest delta from current `swift run` workflow |
| Mac App Store | Mac App Distribution | No (MAS handles it) | Requires native auth replacement (no shelling out to `gh` from a sandboxed app) | Required | Blocked by sandbox + review process |
| Homebrew cask | Wraps a Developer-ID-signed Direct build | Yes (inherits from Direct build) | Works as-is | n/a | Good for staged rollout, but still requires a Direct build first |
| TestFlight | Mac App Distribution | No (App Store Connect handles it) | Requires native auth replacement | Required (MAS-adjacent) | Blocked by the same sandbox constraints as MAS |

- **Direct distribution.** Dominant blocker for the prototype is signing identity availability and notarization credentials, both of which are out-of-scope until the user supplies them; once supplied, this channel is the shortest path because the existing `gh`-based GitHub auth keeps working.
- **Mac App Store.** Dominant blocker is the sandbox: a sandboxed app cannot inherit the user's shell `PATH`, cannot reliably spawn `/opt/homebrew/bin/python3` or `gh`, and cannot read `~/.config/gh`. Going MAS implies replacing the entire `gh`-based GitHub auth path with a native OAuth flow before submission, which is its own multi-slice project.
- **Homebrew cask.** Dominant blocker is that a cask is a thin wrapper around a Direct build; choosing it does not avoid any of the Direct-distribution prerequisites and adds a separate tap/cask repository to maintain.
- **TestFlight.** Dominant blocker is the same sandbox constraint as MAS plus an App Store Connect record, so it inherits the entire MAS readiness cost without the public-distribution payoff.

## Python helper runtime-distribution matrix

| Option | `tomllib` 3.11+ satisfied | Self-containedness | Sibling-discipline impact | Signing impact | `~/.agendum` path impact |
| --- | --- | --- | --- | --- | --- |
| Sibling `../agendum` checkout | Depends on user's Python | None (developer-only) | None (current state) | n/a | None |
| Vendor `agendum` source tarball into this repo | Depends on user's Python | Partial (source vendored, runtime not) | Breaks `Scripts/python_coverage.py` and `Tests/test_backend_helper*.py` until CI is updated | n/a | None |
| PyInstaller-bundled helper executable | Yes (frozen interpreter) | Full | Requires re-vendor of `agendum` into the spec | Signs the bundled binary; nested signing for the `.app` if embedded | None directly; helper still writes to `~/.agendum` unless changed |
| py2app | Yes (frozen interpreter) | Full | Requires re-vendor of `agendum` into the setup script | Signs the bundled binary; nested signing for the `.app` if embedded | None directly |
| System `/usr/bin/python3` + `pip install agendum` | Yes (macOS 14+ ships 3.11+) | None | Breaks helper coverage script (helper imports change) | n/a | None directly |
| Homebrew `python@3.11` as documented prerequisite | Yes | None | None for development; production users must install Homebrew | n/a | None directly |

- **Sibling checkout.** Dominant blocker for shipping is that it is not user-shippable; it is the current development-time choice and CI replicates it via a sibling checkout step in `.github/workflows/test.yml`.
- **Vendor source tarball.** Dominant cost is that vendoring duplicates `../agendum` into this repo and invalidates the current sibling-checkout discipline used by both helper coverage and CI; it does not solve the runtime question (the user still has to bring a Python 3.11+ interpreter).
- **PyInstaller-bundled helper.** Dominant cost is build complexity: a `.spec` file targeting `Backend/agendum_backend/helper.py` (the importable module, not the entrypoint shim), nested code-signing inside the `.app`, and a binary that must be re-frozen on every `agendum` update. Buys full self-containedness in exchange.
- **py2app.** Dominant cost is similar to PyInstaller plus the maintenance signal of a less-active toolchain; it is included for completeness because it is Mac-native and predates PyInstaller's macOS support.
- **System `/usr/bin/python3`.** Dominant blocker is that it forces a `pip install agendum` step into first-run and ties the user's Python version to whatever Apple ships; macOS 14 ships Python 3.11.x but earlier macOS versions do not, which would push the minimum-macOS floor up.
- **Homebrew `python@3.11` prerequisite.** Dominant blocker is that it externalizes a dependency the user must install before the app works; the prototype already implicitly does this (development runs prefer Homebrew Python paths), so the cost is making it explicit in user-facing docs.

## Interactions with prior decisions
- Helper-owned SQLite (no direct Swift DB access; `docs/decisions.md` 2026-04-28): bundling decisions do not need to touch this; SQLite ownership stays inside the helper regardless of how the helper is shipped.
- `gh` Finder-launch PATH issue (`docs/handoff.md` Risks): Finder-launched apps do not inherit shell `PATH`, so any future bundle slice must surface a `gh` discovery story (probe well-known paths, prompt the user, or replace `gh` outright) regardless of which distribution channel is chosen.
- Sibling-checkout discipline (`docs/decisions.md` 2026-04-28 CI entry): any Python runtime option that requires vendoring `../agendum` invalidates the current `Scripts/python_coverage.py` flow and the `Tests/test_backend_helper*.py` import path until CI is updated to point at the vendored copy.
- No `.xcodeproj` constraint (`docs/decisions.md` 2026-04-28 SwiftPM-first entry): MAS submission later is harder from a SwiftPM-only repo than from a typical Xcode app template; this is a known cost of the SwiftPM-first decision and should be marked as such rather than re-litigated when packaging is scoped.
- `tomllib` 3.11+ requirement (`docs/decisions.md` 2026-04-30 development runner entry): PyInstaller and bundled-Python options carry an explicit Python-version commitment; the floor is 3.11. System-Python and Homebrew-Python options inherit the same floor.
- Backend layout: `Backend/agendum_backend_helper.py` is a one-line entrypoint shim; the importable helper module is `Backend/agendum_backend/helper.py`. PyInstaller specs and any future vendoring passes target the module, not the entrypoint shim.

## Prototype-phase recommendation
Continue developer-only `swift run AgendumMac` for the prototype phase. Defer the distribution-channel pick and the Python runtime pick to user input before scoping any code-bearing packaging slice. The next code-bearing slice (likely `Scripts/build_app_bundle.sh` producing an unsigned `.app`) can be scoped after answers to the deferred decisions are recorded in `docs/decisions.md`.

## Deferred decisions
The following questions should be answered, and the answers recorded in `docs/decisions.md`, before any code-bearing packaging slice begins. Each is framed as a yes/no or pick-one for clarity.

1. Distribution channel for the prototype phase: pick one of Direct / MAS / Homebrew cask / TestFlight / none yet.
2. Code signing identity availability: do you have a Developer ID Application certificate? a Mac App Distribution certificate? defer entirely?
3. Notarization credentials: `xcrun notarytool` keychain profile, App Store Connect API key, or unsigned-only?
4. Python helper runtime strategy for production: pick one of sibling / vendor agendum / PyInstaller / py2app / system `python3` / Homebrew `python@3.11`.
5. Helper-process production layout: pick one of inside `Agendum.app/Contents/Resources/Backend/` / alongside the `.app` bundle / `~/Library/Application Support/agendum/` / `$PATH`-discoverable.
6. `gh` dependency posture: require user-installed `gh` with a repair UX, bundle a pinned `gh`, or replace with native GitHub auth later?
7. `~/.agendum` path policy: keep `~/.agendum`, or migrate to `~/Library/Application Support/agendum/` for sandbox/MAS compatibility?
8. Bundle identity: pick `CFBundleIdentifier` (for example `com.danseely.agendum-mac`) and `CFBundleName`. (answered 2026-05-02: see decisions.md)
9. App icon and branding: is an icon asset available now, or use a placeholder for the first slice? (answered 2026-05-02: see decisions.md)
10. App version policy: fixed `0.1.0` until first release, or pull from git tags? (answered 2026-05-02: see decisions.md)
