#!/bin/zsh
# Rebuilds Resources/AppIcon.icns from Resources/AppIcon-source.png (artwork on the macOS icon grid).
set -euo pipefail
cd "$(dirname "$0")/.."
TMP=$(mktemp -d)
mkdir -p "$TMP/AppIcon.iconset"
swift Scripts/render-icon.swift Resources/AppIcon-source.png "$TMP/AppIcon.iconset" "${ICON_ZOOM:-1}"   # ICON_ZOOM=1.03 trims art that has its own edge
iconutil -c icns "$TMP/AppIcon.iconset" -o Resources/AppIcon.icns
rm -rf "$TMP"
echo "Wrote Resources/AppIcon.icns"
