#!/bin/bash
# Regenerates Assets/AppIcon.icns from Assets/AppIcon.svg on macOS (Quick Look renders the SVG,
# sips resizes, iconutil packs). The committed .icns means you only need this after editing the SVG.
# For macOS 26's layered Liquid Glass icon, import Assets/IconLayers/*.svg into Icon Composer.
set -euo pipefail
cd "$(dirname "$0")/../Assets"

TMP="$(mktemp -d)"
qlmanage -t -s 1024 -o "$TMP" AppIcon.svg >/dev/null
SRC="$TMP/AppIcon.svg.png"
SET="$TMP/AppIcon.iconset"
mkdir -p "$SET"
for size in 16 32 128 256 512; do
    sips -z $size $size "$SRC" --out "$SET/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) "$SRC" --out "$SET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o AppIcon.icns
cp "$SRC" AppIcon-1024.png
rm -rf "$TMP"
echo "Wrote Assets/AppIcon.icns"
