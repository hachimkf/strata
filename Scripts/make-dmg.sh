#!/bin/zsh
# Build a drag-to-Applications disk image from the already-built app.
set -euo pipefail
cd "$(dirname "$0")/.."
APP=build/Strata.app
[[ -d "$APP" ]] || { echo "Run Scripts/build-app.sh first"; exit 1; }
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
OUT="build/Strata-$VERSION.dmg"
STAGING=$(mktemp -d "${TMPDIR:-/tmp}/strata-dmg.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT
ditto "$APP" "$STAGING/Strata.app"
ln -s /Applications "$STAGING/Applications"
cp LICENSE "$STAGING/License.txt"
hdiutil create -ov -volname "Strata $VERSION" -srcfolder "$STAGING" -format UDZO "$OUT"
hdiutil verify "$OUT"
(cd build && shasum -a 256 "Strata-$VERSION.dmg" > "Strata-$VERSION.dmg.sha256.txt")
echo "Built $(pwd)/$OUT"
