# agendum_engine

This directory is a vendored fork of the `agendum` Python engine. It is the
backend that the Mac app's helper subprocess imports from. The `agendum-mac`
repo now owns this code; the upstream sibling repo is no longer load-bearing.

## Origin

- Upstream: https://github.com/danseely/agendum
- Forked from upstream commit: `b62a45c6a28f8ffd4b57a597de4744dc83d0d94d`
- Forked on: 2026-05-04
- Method: flat copy of `src/agendum/` (subtree history was not preserved; see
  `docs/decisions.md` 2026-05-04 entry for rationale).

## Layout

```
Backend/agendum_engine/
  LICENSE              # Upstream Apache-2.0 license, preserved verbatim
  README.md            # This file
  agendum/             # The Python package (import name: agendum)
```

The package import name is unchanged (`import agendum.config`, etc.) so
existing call sites in `Backend/agendum_backend/helper.py` and the test suite
do not need import-path edits beyond a single `sys.path` entry pointing at
`Backend/agendum_engine/`.

## Divergence policy

This fork is **not** kept in sync with the upstream `danseely/agendum`
repository. The Mac app evolves the engine here; upstream changes are not
back-ported. Subsequent epic-B leaves (B2 through B5) progressively port
modules of this Python engine to Swift; epic-B leaf B6 deletes this directory
once the helper subprocess is retired.

## License

Apache License 2.0. See `LICENSE` in this directory; the file is preserved
verbatim from upstream.
