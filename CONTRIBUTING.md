# Contributing to Agendum

Agendum is a personal-use prototype maintained by one developer, but outside contributions are welcome. For anything non-trivial, open an issue first so we can sanity-check scope before you spend time on a PR.

## Getting started

Requirements:

- macOS 14 (Sonoma) or newer.
- Swift 6 toolchain (ships with current Xcode).

Clone and build:

```
git clone https://github.com/danseely/agendum-mac.git
cd agendum-mac
swift build
swift test
```

To produce a runnable `.app` bundle the same way CI does:

```
bash Scripts/build_app_bundle.sh
open .build/Agendum.app
```

See the [README](README.md) for first-run setup (GitHub auth, workspace config).

## Branches and PRs

- Branch off `main`. Don't push directly to `main`.
- Name branches `codex/<topic>` to match the established convention (skim `git log --oneline` to see it in practice) or use any other short, descriptive name.
- PRs target `main`.
- Merge style: small, atomic PRs are **squash-merged**. Intentional history-preserving milestones get a **merge commit** — the `feature/mac-prototype` → `main` graduation in PR #2 was that kind of merge. Default is squash for everything else.
- Reference any related issue in the PR body (`Fixes #N`).
- End the PR body with this footer line:

  ```
  🤖 Generated with [Claude Code](https://claude.com/claude-code)
  ```

  Required for AI-assisted work; optional for human-authored PRs.

## Validation gates

CI runs on every PR via `.github/workflows/test.yml` (job `Test`, currently pinned to `macos-latest` — Sequoia / Swift 6). The gates, in order:

- `python3 -m unittest discover -s Tests` (Python parity tests)
- `jq empty docs/features.json` (feature ledger is well-formed JSON)
- `swift build`
- `swift test --enable-code-coverage`
- `Scripts/build_app_bundle.sh` plus `plutil -lint .build/Agendum.app/Contents/Info.plist` (app bundle smoke)
- `git diff --check` (no whitespace errors)
- A grep that fails the build if stale Python-helper runtime references reappear

`.github/workflows/test.yml` is the source of truth — if this list and the workflow disagree, the workflow wins.

## Code style

There is no enforced formatter today. Match the surrounding code: existing indentation, naming, and comment density. A SwiftFormat or SwiftLint baseline is being tracked in issue #78 — when it lands, this section will be updated to point at the configuration.

## Where things live

See the README's [Project layout](README.md#project-layout) section. Not duplicated here so it can't drift.

## Releases

Every push to `main` triggers `.github/workflows/release.yml`, which builds the app, packages it as a DMG, and publishes a GitHub prerelease tagged `v0.1.0-dev.<short-sha>` with an ad-hoc-signed (not Developer-ID-signed, not notarized) DMG attached. Contributors don't need to think about this — it's automatic on merge.

## Planning artifacts

`docs/project-state.md` and `docs/features.json` hold the long-running planning state — current goal, constraints, decisions, in-flight slices. Updates to those typically ride along with the relevant implementation PR rather than getting their own doc-only PR.
