# Agendum

A native macOS viewer for your GitHub work: pull requests you authored, reviews requested of you, issues, and a small set of manual tasks. One window, one inbox, kept fresh by a background syncer.

Agendum is a personal-use tool for one developer's daily GitHub workflow. It is working software, not a sketch — but it has not been hardened for general distribution. Treat it accordingly.

<!-- TODO: screenshot -->

## Status

- Working software, used daily by its author.
- Personal-use prototype. No code-signing, no notarization, no telemetry, no auto-update.
- No `LICENSE` file yet. Open-source readiness (license, contribution guide, signed builds) is a follow-up, not a promise.
- Born as a Swift-native rewrite of a sibling Python terminal CLI. The Mac app stands on its own — no Python, no helper process, no sibling checkout at runtime.

## Requirements

- macOS 14 (Sonoma) or newer.
- A GitHub account.
- [`gh`](https://cli.github.com) installed and authenticated. Agendum currently reuses the `gh` CLI token for GitHub access. Native OAuth Device Flow plus Keychain storage is planned.

## Install (prebuilt DMG)

Every push to `main` publishes an unsigned, unnotarized DMG as a GitHub prerelease tagged `v0.1.0-dev.<short-sha>`.

1. Grab the latest DMG from the [Releases page](../../releases) — pick the newest `Agendum-*.dmg`.
2. Open the DMG and drag **Agendum** into **Applications**.
3. First launch only, clear the download quarantine. The build is ad-hoc signed but not Developer-ID signed or notarized, so macOS marks the download as untrusted. Either:
   - **GUI path:** double-click Agendum. macOS will say "Agendum can't be opened because Apple cannot check it for malicious software." Click **Done**, then open **System Settings → Privacy & Security**, scroll to the bottom, and click **Open Anyway** next to the Agendum line. Confirm at the second prompt. After this, normal double-click works.
   - **Terminal path:** strip the quarantine attribute and open normally.
     ```
     xattr -dr com.apple.quarantine /Applications/Agendum.app
     ```

   The older "right-click → Open" trick from pre-Sequoia macOS no longer applies to unsigned apps — use one of the two paths above.
4. (Optional) Verify the download against the checksum sidecar:
   ```
   shasum -a 256 Agendum-<version>.dmg
   # compare against Agendum-<version>.dmg.sha256
   ```

## Build from source

Agendum is a pure SwiftPM project — there is no Xcode project to open. Swift 6 toolchain shipping with current Xcode works.

```
git clone https://github.com/danseely/agendum-mac.git
cd agendum-mac
swift build
swift run AgendumMac
```

`swift run` launches the app from the package's debug binary, which is fine for hacking on it. To produce a proper `.app` you can drag into `/Applications`, use the bundle script:

```
bash Scripts/build_app_bundle.sh
open .build/Agendum.app
```

To produce a full DMG locally (same artifact CI publishes):

```
bash Scripts/build_dmg.sh
# writes .build/Agendum-<version>.dmg and .build/Agendum-<version>.dmg.sha256
```

Run the test suite with `swift test`.

## First-run setup

### 1. Authenticate with GitHub

Agendum reads the token managed by the `gh` CLI:

```
gh auth login
```

Make sure the resulting token has `repo` and `read:org` scopes — the syncer needs both to list pull requests and review requests across the repos and orgs it scans.

### 2. Configure a workspace

Agendum stores per-workspace state under `~/.agendum/`. The base workspace lives at `~/.agendum/`; additional GitHub-account workspaces live under `~/.agendum/workspaces/<owner>/`, switchable from the sidebar.

Each workspace has a `config.toml` declaring which orgs and repos to sync. If you let Agendum create one for you on first launch, it will seed `[github].orgs` with the workspace's namespace. To edit by hand:

```toml
[github]
# GitHub org(s) to scan
orgs = ["my-org"]

# Explicit repo whitelist ("owner/repo" format).
# If set, only these repos are synced - org-wide discovery is skipped.
repos = []

# Repos to exclude (optional, "owner/repo" format)
exclude_repos = ["my-org/archived-thing"]

[sync]
# Poll interval in seconds
interval = 120

[display]
# Seconds after focus before marking items seen
seen_delay = 3
```

Notes:

- `orgs` discovers repos owned by each org. `repos` is an allow-list that bypasses discovery. They can be combined.
- `exclude_repos` is applied after discovery.
- The workspace directory is created at `0700`; the config file at `0600`.

### 3. Storage

Each workspace owns its SQLite database at `~/.agendum/agendum.db` (or `~/.agendum/workspaces/<owner>/agendum.db`). The app is the sole writer — no migrations to run by hand.

## Project layout

SwiftPM modules under `Sources/`:

- `AgendumModel` — value types shared across modules. No I/O.
- `AgendumMacStore` — GRDB-backed SQLite persistence.
- `AgendumGitHub` — GitHub transport: REST + GraphQL over `URLSession`.
- `AgendumSync` — sync engine and workspace config. Coordinates transport and store against the syncer spec.
- `AgendumFeature` — SwiftUI views, view models, and feature logic.
- `AgendumAppServices` — wires features, sync, storage, and transport into runnable services.
- `AgendumMac` — the app entry point (executable target).

Tests live in `Tests/<Module>Tests/`. Run them with `swift test`.

The released app bundle is assembled by `Scripts/build_app_bundle.sh` from `Sources/AgendumMac/Info.plist.template` and `Resources/AppIcon.icns`. The icon is currently a loose `.icns`; a Tahoe Icon Composer asset is a follow-up.

## Releases

`.github/workflows/release.yml` runs on every push to `main`:

1. `swift build -c release` and `swift test`.
2. `Scripts/build_app_bundle.sh` builds the `.app`.
3. `Scripts/build_dmg.sh` packages it into a versioned DMG with a SHA-256 sidecar.
4. `Scripts/verify_dmg.sh` smoke-tests the artifact.
5. A GitHub prerelease tagged `v0.1.0-dev.<short-sha>` is created with the DMG and checksum attached.

Builds are unsigned and unnotarized by design — distribution polish is deferred until the app graduates beyond personal use.

## Further reading

- [`docs/project-state.md`](docs/project-state.md) — current planning state and what's in flight.
- [`docs/syncer-spec.md`](docs/syncer-spec.md) — behavior contract for the sync engine. If syncer behavior surprises you, this is the source of truth.
