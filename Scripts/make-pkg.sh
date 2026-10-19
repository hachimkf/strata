#!/bin/zsh
# Wraps build/Strata.app into a macOS Installer package: build/Strata-<version>.pkg
# Welcome page, branded background, installs into /Applications, quits an old copy first
# and opens Strata when done. Signs with a "Developer ID Installer" certificate if one exists.
set -euo pipefail
cd "$(dirname "$0")/.."

APP=build/Strata.app
[[ -d "$APP" ]] || { echo "Run Scripts/build-app.sh first"; exit 1; }
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
OUT="build/Strata-$VERSION.pkg"

WORK=build/pkg
rm -rf "$WORK" "$OUT"
mkdir -p "$WORK/root/Applications"
cp -R "$APP" "$WORK/root/Applications/"

# Always install into /Applications (never "upgrade" a copy found elsewhere on disk).
pkgbuild --analyze --root "$WORK/root" "$WORK/component.plist" >/dev/null
plutil -replace 0.BundleIsRelocatable -bool false "$WORK/component.plist"
plutil -replace 0.BundleHasStrictIdentifier -bool true "$WORK/component.plist"

pkgbuild --quiet --root "$WORK/root" --component-plist "$WORK/component.plist" \
  --identifier com.lakhloufi.strata --version "$VERSION" --install-location / \
  --scripts Installer/scripts "$WORK/Strata-component.pkg"

sed "s/__VERSION__/$VERSION/" Installer/distribution.xml > "$WORK/distribution.xml"

SIGN=()
INSTALLER_ID="${STRATA_INSTALLER_IDENTITY:-$(security find-identity -v | grep -m1 '"Developer ID Installer' | sed -E 's/.*"(.*)"/\1/' || true)}"
[[ -n "$INSTALLER_ID" ]] && SIGN=(--sign "$INSTALLER_ID")

productbuild --quiet --distribution "$WORK/distribution.xml" --resources Installer/resources \
  --package-path "$WORK" $SIGN "$OUT"
rm -rf "$WORK"
echo "Built $(pwd)/$OUT${INSTALLER_ID:+ (signed: $INSTALLER_ID)}"
