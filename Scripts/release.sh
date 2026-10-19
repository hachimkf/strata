#!/bin/zsh
# Publishes a Strata release.
#
#   Scripts/release.sh [patch|minor|major|current|X.Y.Z] "Release notes" [--local]
#
# 1. bumps CFBundleShortVersionString / CFBundleVersion in Resources/Info.plist
# 2. runs the self-checks, builds a universal (Apple Silicon + Intel) app, signs it (hardened runtime)
# 3. makes build/Strata-<version>.dmg (+ .sha256, which the in-app updater verifies)
# 4. notarizes and staples when signed with a Developer ID and $STRATA_NOTARY_PROFILE is set
#    (create once: xcrun notarytool store-credentials strata --apple-id … --team-id … )
# 5. unless --local: commits, tags and pushes the source, then creates the GitHub release on
#    hachimkf/strata-releases (public), which the app checks for updates.
set -euo pipefail
cd "$(dirname "$0")/.."

BUMP="${1:-patch}"
NOTES="${2:-}"
LOCAL=0
for arg in "$@"; do [[ "$arg" == "--local" ]] && LOCAL=1; done
[[ "$BUMP" == "--local" ]] && BUMP=patch

RELEASES_REPO="hachimkf/strata-releases"
PLIST=Resources/Info.plist
PB=/usr/libexec/PlistBuddy
CUR=$($PB -c "Print CFBundleShortVersionString" $PLIST)
BUILD=$($PB -c "Print CFBundleVersion" $PLIST)
IFS=. read -r MA MI PA <<< "$CUR"
case $BUMP in
  current) NEW=$CUR ;;
  patch)   NEW="$MA.$MI.$((PA + 1))" ;;
  minor)   NEW="$MA.$((MI + 1)).0" ;;
  major)   NEW="$((MA + 1)).0.0" ;;
  <->.<->.<->) NEW=$BUMP ;;
  *) echo "Unknown version bump: $BUMP"; exit 1 ;;
esac
if [[ "$NEW" != "$CUR" ]]; then
  BUILD=$((BUILD + 1))
  $PB -c "Set CFBundleShortVersionString $NEW" -c "Set CFBundleVersion $BUILD" $PLIST
fi
echo "▸ Strata $NEW (build $BUILD)"

echo "▸ Self-checks"
swift build --product strata-selftest >/dev/null
.build/debug/strata-selftest | tail -1

echo "▸ Universal build"
Scripts/build-app.sh --universal

APP=build/Strata.app
DMG="build/Strata-$NEW.dmg"
IDENTITY=$(codesign -dvv "$APP" 2>&1 | sed -n 's/^Authority=\(Developer ID Application.*\)/\1/p' | head -1)

echo "▸ Disk image"
STAGE=build/dmg
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "Strata $NEW" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"
[[ -n "$IDENTITY" ]] && codesign --force --timestamp --sign "$IDENTITY" "$DMG"

if [[ -n "$IDENTITY" && -n "${STRATA_NOTARY_PROFILE:-}" ]]; then
  echo "▸ Notarizing (a few minutes)"
  xcrun notarytool submit "$DMG" --keychain-profile "$STRATA_NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
  NOTARIZED=1
else
  NOTARIZED=0
  echo "  Not notarized: needs a Developer ID Application certificate and STRATA_NOTARY_PROFILE."
fi

(cd build && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256")
echo "▸ $(pwd)/$DMG"
cat "$DMG.sha256"

if [[ $LOCAL == 1 ]]; then
  echo "✓ Local build only (--local): nothing committed or published."
  exit 0
fi

[[ -z "$NOTES" ]] && NOTES="Strata $NEW"
if [[ $NOTARIZED == 0 ]]; then
  NOTES="$NOTES

First launch: right-click Strata in Applications › Open (this build isn't notarized by Apple yet)."
fi

echo "▸ Source: commit, tag, push"
git add -A
git commit -q -m "Release v$NEW" || true
git tag -f "v$NEW"
git push -q origin HEAD
git push -q -f origin "v$NEW"

echo "▸ GitHub release on $RELEASES_REPO"
gh release create "v$NEW" "$DMG" "$DMG.sha256" --repo "$RELEASES_REPO" --title "Strata $NEW" --notes "$NOTES"
echo "✓ Released Strata $NEW"
