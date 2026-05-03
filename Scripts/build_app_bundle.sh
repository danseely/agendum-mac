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

sed \
  -e "s/__SHORT_VERSION__/$SHORT_VERSION/g" \
  -e "s/__BUNDLE_VERSION__/$BUNDLE_VERSION/g" \
  "$PLIST_TEMPLATE" > "$APP_BUNDLE/Contents/Info.plist"

plutil -lint "$APP_BUNDLE/Contents/Info.plist" >/dev/null

echo "Built $APP_BUNDLE (version $SHORT_VERSION, build $BUNDLE_VERSION)"
