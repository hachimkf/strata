#!/bin/zsh
# Builds Strata.app with Swift Package Manager (no Xcode needed) into ./build/Strata.app
# Usage: Scripts/build-app.sh [--open] [--universal]
#
# Signing: $STRATA_SIGN_IDENTITY, else a "Developer ID Application" certificate, else "Apple Development",
# else ad-hoc. Other Macs need right-click › Open until the app is notarized (Developer ID only).
# Always signs with the hardened runtime.
set -euo pipefail
cd "$(dirname "$0")/.."

OPEN=0
ARCHS=()
for arg in "$@"; do
  case $arg in
    --open) OPEN=1 ;;
    --universal) ARCHS=(--arch arm64 --arch x86_64) ;;
  esac
done

swift build -c release --product Strata $ARCHS
BIN="$(swift build -c release --product Strata $ARCHS --show-bin-path)/Strata"

APP=build/Strata.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Strata"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Signing identity, best first. A real certificate gives Strata a stable identity, so macOS remembers
# folder / Full Disk Access permissions across builds and updates (ad-hoc signatures change every build).
find_identity() { security find-identity -v -p codesigning | grep -m1 "\"$1" | sed -E 's/.*"(.*)"/\1/' || true; }
IDENTITY="${STRATA_SIGN_IDENTITY:-$(find_identity "Developer ID Application")}"
[[ -z "$IDENTITY" ]] && IDENTITY="$(find_identity "Apple Development")"
if [[ -n "$IDENTITY" ]]; then
  TS=--timestamp
  [[ "$IDENTITY" == Apple\ Development* ]] && TS=--timestamp=none
  codesign --force --options runtime $TS --entitlements Resources/Strata.entitlements --sign "$IDENTITY" "$APP"
  echo "Signed with: $IDENTITY"
else
  codesign --force --options runtime --entitlements Resources/Strata.entitlements --sign - "$APP"
  echo "Signed ad-hoc (no certificate found: macOS will ask for folder access again after each update)"
fi
codesign --verify --strict "$APP"
echo "Built $(pwd)/$APP ($(lipo -archs "$APP/Contents/MacOS/Strata"))"

if [[ $OPEN == 1 ]]; then
  pkill -x Strata 2>/dev/null && sleep 1 || true
  open "$APP"
fi
