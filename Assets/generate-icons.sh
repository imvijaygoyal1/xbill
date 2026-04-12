#!/usr/bin/env bash
# generate-icons.sh
# Exports xbill-icon.svg to all required iOS icon sizes using rsvg-convert.
#
# Requirements:
#   brew install librsvg
#
# Usage:
#   cd Assets && bash generate-icons.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$SCRIPT_DIR/xbill-icon.svg"
OUT="$SCRIPT_DIR/AppIcon.appiconset"

if ! command -v rsvg-convert &>/dev/null; then
  echo "Error: rsvg-convert not found. Install with: brew install librsvg"
  exit 1
fi

mkdir -p "$OUT"

export_icon() {
  local size=$1
  local filename=$2
  echo "  Exporting ${filename} (${size}x${size})"
  rsvg-convert -w "$size" -h "$size" -f png -o "$OUT/$filename" "$SRC"
}

echo "Generating iOS icons from $SRC..."

# iPhone notification
export_icon 20   "Icon-20@1x.png"
export_icon 40   "Icon-20@2x.png"
export_icon 60   "Icon-20@3x.png"

# iPhone settings / Spotlight
export_icon 29   "Icon-29@1x.png"
export_icon 58   "Icon-29@2x.png"
export_icon 87   "Icon-29@3x.png"

# iPhone Spotlight
export_icon 40   "Icon-40@1x.png"
export_icon 80   "Icon-40@2x.png"
export_icon 120  "Icon-40@3x.png"

# iPhone home screen
export_icon 120  "Icon-60@2x.png"
export_icon 180  "Icon-60@3x.png"

# iPad home screen
export_icon 76   "Icon-76@1x.png"
export_icon 152  "Icon-76@2x.png"

# iPad Pro home screen (167 = 83.5 @2x)
export_icon 167  "Icon-83.5@2x.png"

# App Store
export_icon 1024 "Icon-1024.png"

echo ""
echo "Done. PNGs written to $OUT/"
echo "Copy $OUT/ into your Xcode project's Assets.xcassets/AppIcon.appiconset/"
