#!/bin/zsh
# Builds Strata.app with Swift Package Manager (no Xcode needed) into ./build/Strata.app
# Usage: Scripts/build-app.sh [--open] [--universal]
#
# Signing: uses $STRATA_SIGN_IDENTITY, else the first "Developer ID Application" certificate in the
# keychain, else an ad-hoc signature (runs on this Mac; other Macs need right-click › Open).
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

IDENTITY="${STRATA_SIGN_IDENTITY:-$(security find-identity -v -p codesigning | grep -m1 '"Developer ID Application' | sed -E 's/.*"(.*)"/\1/' || true)}"
if [[ -n "$IDENTITY" ]]; then
  codesign --force --options runtime --timestamp --entitlements Resources/Strata.entitlements --sign "$IDENTITY" "$APP"
  echo "Signed with: $IDENTITY"
else
  codesign --force --options runtime --entitlements Resources/Strata.entitlements --sign - "$APP"
  echo "Signed ad-hoc (no Developer ID certificate found)"
fi
codesign --verify --strict "$APP"
echo "Built $(pwd)/$APP ($(lipo -archs "$APP/Contents/MacOS/Strata"))"

if [[ $OPEN == 1 ]]; then
  pkill -x Strata 2>/dev/null && sleep 1 || true
  open "$APP"
fi
