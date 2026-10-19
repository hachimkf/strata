#!/bin/zsh
# Builds Strata.app with Swift Package Manager (no Xcode needed) into ./build/Strata.app
# Usage: Scripts/build-app.sh [--open]
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product Strata

APP=build/Strata.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Strata "$APP/Contents/MacOS/Strata"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"

# Ad-hoc signature so macOS will run it locally.
codesign --force --sign - --timestamp=none "$APP" >/dev/null
echo "Built $(pwd)/$APP"

if [[ "${1:-}" == "--open" ]]; then
  pkill -x Strata 2>/dev/null || true
  open "$APP"
fi
