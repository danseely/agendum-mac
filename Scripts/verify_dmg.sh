#!/usr/bin/env bash
#
# Mounts the DMG produced by Scripts/build_dmg.sh, verifies its contents
# (the .app launches its plutil check, the /Applications symlink resolves,
# the sidecar SHA256 matches), then unmounts. Non-destructive — leaves no
# state behind even on failure.
#
# Run with no args to verify the most recently built .build/Agendum-*.dmg,
# or pass an explicit DMG path. Exits non-zero on any check failure.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

APP_NAME="Agendum"

if [ $# -gt 0 ]; then
  DMG_PATH="$1"
else
  DMG_PATH="$(ls -t .build/${APP_NAME}-*.dmg 2>/dev/null | head -1 || true)"
fi

if [ -z "${DMG_PATH:-}" ] || [ ! -f "$DMG_PATH" ]; then
  echo "DMG not found. Run Scripts/build_dmg.sh first, or pass a DMG path." >&2
  exit 1
fi

SHA_PATH="${DMG_PATH}.sha256"
if [ ! -f "$SHA_PATH" ]; then
  echo "Missing sidecar checksum: ${SHA_PATH}" >&2
  exit 1
fi

echo "Verifying $DMG_PATH"

# 1. Checksum match.
EXPECTED="$(awk '{print $1}' "$SHA_PATH")"
ACTUAL="$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"
if [ "$EXPECTED" != "$ACTUAL" ]; then
  echo "SHA256 mismatch" >&2
  echo "  expected: $EXPECTED" >&2
  echo "  actual:   $ACTUAL" >&2
  exit 1
fi
echo "  SHA256 OK"

# 2. Mount (read-only by default), structure checks, unmount. The detach
#    runs in trap so it fires even on early exit. Use the resolved path so
#    the unmount matches macOS's /private/tmp-style mount reporting.
MOUNT_DIR="$(mktemp -d /tmp/agendum-dmg-verify.XXXXXX)"
MOUNT_DIR="$(cd "$MOUNT_DIR" && pwd -P)"
cleanup() {
  # Always attempt detach; harmless when nothing's mounted, correct when the
  # script exits early after `hdiutil attach` succeeds.
  hdiutil detach "$MOUNT_DIR" -quiet 2>/dev/null || true
  rmdir "$MOUNT_DIR" 2>/dev/null || true
}
trap cleanup EXIT

hdiutil attach "$DMG_PATH" -mountpoint "$MOUNT_DIR" -nobrowse -quiet

MOUNTED_APP="${MOUNT_DIR}/${APP_NAME}.app"
if [ ! -d "$MOUNTED_APP" ]; then
  echo "DMG missing ${APP_NAME}.app at the volume root" >&2
  exit 1
fi
echo "  ${APP_NAME}.app present"

if [ ! -L "${MOUNT_DIR}/Applications" ]; then
  echo "DMG missing /Applications drag-target symlink" >&2
  exit 1
fi
echo "  /Applications symlink present"

# Info.plist must parse and the embedded executable must be executable —
# catches "we shipped a broken bundle" cleanly. plutil -lint exits 0 on
# valid plists.
plutil -lint "${MOUNTED_APP}/Contents/Info.plist" >/dev/null
echo "  Info.plist lints clean"

EXEC_NAME="$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "${MOUNTED_APP}/Contents/Info.plist")"
EXEC_PATH="${MOUNTED_APP}/Contents/MacOS/${EXEC_NAME}"
if [ ! -x "$EXEC_PATH" ]; then
  echo "DMG missing executable bit on ${EXEC_PATH}" >&2
  exit 1
fi
echo "  CFBundleExecutable (${EXEC_NAME}) is executable"

# Useful in CI logs and as a downstream confirmation.
SHORT_VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "${MOUNTED_APP}/Contents/Info.plist")"
BUNDLE_VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "${MOUNTED_APP}/Contents/Info.plist")"
echo "  Version: ${SHORT_VERSION} (build ${BUNDLE_VERSION})"

echo "DMG OK"
