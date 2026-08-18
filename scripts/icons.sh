#!/bin/bash
# Regenerates assets/AppIcon.icns and the menu bar PNGs from the SVGs in
# assets/. Rendering goes through NSImage (rasterize.swift): qlmanage would
# flatten SVG transparency onto white, which turns the template glyph into a
# solid square and puts white corners on the icns.
set -euo pipefail
cd "$(dirname "$0")/.."

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
render() { swift scripts/rasterize.swift "$@"; }

# App icon: full-bleed. macOS 26 masks legacy icns into its own squircle and
# white-tiles anything with margins, so the pre-26 824px grid inset must NOT
# be applied here.
render assets/app-icon.svg "$TMP/icon-1024.png" 1024
mkdir -p "$TMP/AppIcon.iconset"
for s in 16 32 128 256 512; do
    sips -z $s $s "$TMP/icon-1024.png" --out "$TMP/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
    sips -z $((s * 2)) $((s * 2)) "$TMP/icon-1024.png" --out "$TMP/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$TMP/AppIcon.iconset" -o assets/AppIcon.icns

# Menu bar template glyph, 18pt @1x/@2x, rendered straight from the vector.
render assets/menubar-icon.svg Sources/HolsterKit/Resources/MenuBarIcon.png 18
render assets/menubar-icon.svg "Sources/HolsterKit/Resources/MenuBarIcon@2x.png" 36

echo "Regenerated assets/AppIcon.icns and Sources/HolsterKit/Resources/MenuBarIcon*.png"
