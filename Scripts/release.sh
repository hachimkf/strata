#!/bin/zsh
# Publishes a Strata release.
#
#   Scripts/release.sh [patch|minor|major|current|X.Y.Z] "Release notes" [--local]
#
# 1. bumps CFBundleShortVersionString / CFBundleVersion in Resources/Info.plist
# 2. runs the self-checks, builds a universal (Apple Silicon + Intel) app, signs it (hardened runtime)
# 3. makes the installer build/Strata-<version>.pkg (+ .sha256, which the in-app updater verifies)
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

echo "▸ Installer package"
Scripts/make-pkg.sh
PKG="build/Strata-$NEW.pkg"
SIGNED_PKG=$(pkgutil --check-signature "$PKG" | grep -q "Developer ID Installer" && echo 1 || echo 0)

if [[ $SIGNED_PKG == 1 && -n "${STRATA_NOTARY_PROFILE:-}" ]]; then
  echo "▸ Notarizing (a few minutes)"
  xcrun notarytool submit "$PKG" --keychain-profile "$STRATA_NOTARY_PROFILE" --wait
  xcrun stapler staple "$PKG"
  NOTARIZED=1
else
  NOTARIZED=0
  echo "  Not notarized: needs Developer ID Application + Installer certificates and STRATA_NOTARY_PROFILE."
fi

(cd build && shasum -a 256 "$(basename "$PKG")" > "$(basename "$PKG").sha256")
echo "▸ $(pwd)/$PKG"
cat "$PKG.sha256"

if [[ $LOCAL == 1 ]]; then
  echo "✓ Local build only (--local): nothing committed or published."
  exit 0
fi

[[ -z "$NOTES" ]] && NOTES="Strata $NEW"
if [[ $NOTARIZED == 0 ]]; then
  NOTES="$NOTES

How to install: download Strata-$NEW.pkg, then right-click it › Open › Open (this build isn't notarized by Apple yet, so a plain double-click is blocked the first time). The installer puts Strata in Applications and opens it."
fi

echo "▸ Source: commit, tag, push"
git add -A
git commit -q -m "Release v$NEW" || true
git tag -f "v$NEW"
git push -q origin HEAD
git push -q -f origin "v$NEW"

echo "▸ GitHub release on $RELEASES_REPO"
gh release create "v$NEW" "$PKG" "$PKG.sha256" --repo "$RELEASES_REPO" --title "Strata $NEW" --notes "$NOTES"
echo "✓ Released Strata $NEW"
