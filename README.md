# Agendum Mac

Native macOS shell exploration for agendum.

This is intentionally separate from `../agendum`. The existing terminal app remains the source for the Python engine and current behavior; this repo is for evaluating and building a proper Mac GUI around that workflow.

## Current Shape

- README-only public base branch.
- Prototype work happens on feature branches and pull requests.
- The first implementation branch is `feature/backend-helper`.

## Run

The runnable app scaffold lives on implementation branches, not on `main`.

```bash
swift run AgendumMac
```

## Near-Term Direction

1. Define the backend bridge to the existing Python engine.
2. Extract or reuse a stable task/action API from `../agendum`.
3. Replace sample data with backend-driven task loading.
4. Add Mac-native settings, menu commands, keyboard shortcuts, sync status, and workspace selection.
