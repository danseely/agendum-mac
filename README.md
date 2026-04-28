# Agendum Mac

Native macOS shell exploration for agendum.

This is intentionally separate from `../agendum`. The existing terminal app remains the source for the Python engine and current behavior; this repo is for evaluating and building a proper Mac GUI around that workflow.

## Current Shape

- SwiftUI-first macOS app scaffold.
- Local sample data only.
- Public `main` is README-only; this branch carries the prototype baseline.
- Planning state lives in `docs/`.

## Run

```bash
swift run AgendumMac
```

## Near-Term Direction

1. Define the backend bridge to the existing Python engine.
2. Extract or reuse a stable task/action API from `../agendum`.
3. Replace sample data with backend-driven task loading.
4. Add Mac-native settings, menu commands, keyboard shortcuts, sync status, and workspace selection.
