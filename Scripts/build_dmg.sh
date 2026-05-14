#!/usr/bin/env bash
#
# Builds .build/Agendum-<version>.dmg from the app bundle produced by
# Scripts/build_app_bundle.sh. Idempotent — re-running re-renders both.
#
# Output:
#   .build/Agendum-<version>.dmg          compressed read-only DMG
#   .build/Agendum-<version>.dmg.sha256   sidecar checksum (single line)
#
# The DMG contains the .app and a symlink to /Applications so users get the
# drag-to-install Finder layout when they mount it. No background image, no
# custom window — kept deliberately minimal for an unsigned dev build.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

APP_NAME="Agendum"
BUILD_DIR=".build"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"

# Always rebuild the .app from current source — the release flow can't trust
# stale .build state, and rebuilds are cheap when nothing has changed.
"$SCRIPT_DIR/build_app_bundle.sh"

if [ ! -d "$APP_BUNDLE" ]; then
  echo "build_app_bundle.sh did not produce $APP_BUNDLE" >&2
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_BUNDLE/Contents/Info.plist")"
if [ -z "$VERSION" ]; then
  echo "Could not read CFBundleShortVersionString from $APP_BUNDLE/Contents/Info.plist" >&2
  exit 1
fi

DMG_PATH="${BUILD_DIR}/${APP_NAME}-${VERSION}.dmg"
STAGING_DIR="${BUILD_DIR}/dmg-staging"

# Clean any prior artifacts so hdiutil never sees a stale file.
rm -f "$DMG_PATH" "${DMG_PATH}.sha256"
rm -rf "$STAGING_DIR"

# Ensure staging is reaped on every exit, including hdiutil failure mid-build.
trap 'rm -rf "$STAGING_DIR"' EXIT

# Stage the .app + an /Applications symlink for drag-to-install UX.
mkdir -p "$STAGING_DIR"
cp -R "$APP_BUNDLE" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

# UDZO = compressed read-only. -ov overwrites if the file existed. Volume
# label is unversioned so the mount path is stable across builds — the
# filename carries the version.
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

# Sidecar checksum so releases and downstream users can verify integrity.
# Single line: `<hex>  <filename>` — same shape `shasum -c` consumes.
shasum -a 256 "$DMG_PATH" > "${DMG_PATH}.sha256"
SHA256="$(awk '{print $1}' "${DMG_PATH}.sha256")"

echo "Built ${DMG_PATH}"
echo "Version: ${VERSION}"
echo "SHA256:  ${SHA256}"
