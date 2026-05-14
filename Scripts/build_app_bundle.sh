#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

APP_NAME="Agendum"
SWIFT_PRODUCT="AgendumMac"
BUILD_DIR=".build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
PLIST_TEMPLATE="Sources/AgendumMac/Info.plist.template"
APP_ICON="Resources/AppIcon.icns"

SHORT_VERSION="$(git describe --tags --match 'v*' --dirty --always 2>/dev/null | sed 's/^v//' || true)"
if [ -z "$SHORT_VERSION" ] || ! echo "$SHORT_VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+'; then
  SHORT_VERSION="0.1.0+dev"
fi
# Note: shallow CI clones return truncated rev-list counts. Cosmetic; not a smoke failure.
BUNDLE_VERSION="$(git rev-list HEAD --count 2>/dev/null || echo 1)"

rm -rf "$APP_BUNDLE"
swift build -c release --product "$SWIFT_PRODUCT"

mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BUILD_DIR/release/$SWIFT_PRODUCT" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

if [ ! -f "$APP_ICON" ]; then
  echo "Missing app icon: $APP_ICON" >&2
  exit 1
fi
cp "$APP_ICON" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

sed \
  -e "s/__SHORT_VERSION__/$SHORT_VERSION/g" \
  -e "s/__BUNDLE_VERSION__/$BUNDLE_VERSION/g" \
  "$PLIST_TEMPLATE" > "$APP_BUNDLE/Contents/Info.plist"

plutil -lint "$APP_BUNDLE/Contents/Info.plist" >/dev/null

# Re-sign the whole bundle ad-hoc. The Swift linker ships the binary with a
# linker-injected ad-hoc signature (mandatory on Apple Silicon), but that
# signature predates the resources we just dropped in (Info.plist,
# AppIcon.icns) and there's no Contents/_CodeSignature/CodeResources manifest
# to cover them. On launch from a quarantined DMG that mismatch trips
# Gatekeeper's integrity check, which surfaces as the "Agendum.app is damaged
# and can't be opened" dialog — a dead-end with no GUI escape on macOS 15+.
#
# `codesign --force --deep --sign -` synthesizes the bundle-level manifest
# and re-signs everything ad-hoc. The bundle is still unsigned in the
# Developer-ID sense, so Gatekeeper still rejects on first launch, but it
# rejects with the "unidentified developer" wording which DOES give users a
# working "Open Anyway" button in System Settings → Privacy & Security.
# Full Developer-ID signing + notarization is a separate slice.
codesign --force --deep --sign - "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"

echo "Built $APP_BUNDLE (version $SHORT_VERSION, build $BUNDLE_VERSION)"
