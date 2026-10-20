#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$ROOT/Resources/AppIcon.svg"
OUTPUT="${1:-$ROOT/Resources/AppIcon.icns}"
ICONSET="$(mktemp -d)/AppIcon.iconset"

trap 'rm -rf "$(dirname "$ICONSET")"' EXIT
mkdir -p "$ICONSET"

render_png() {
  local size="$1"
  local output="$2"
  qlmanage -t -s "$size" -o "$(dirname "$output")" "$SOURCE" >/dev/null 2>&1
  mv "$(dirname "$output")/$(basename "$SOURCE").png" "$output"
}

render_png 16 "$ICONSET/icon_16x16.png"
render_png 32 "$ICONSET/icon_16x16@2x.png"
cp "$ICONSET/icon_16x16@2x.png" "$ICONSET/icon_32x32.png"
render_png 64 "$ICONSET/icon_32x32@2x.png"
render_png 128 "$ICONSET/icon_128x128.png"
render_png 256 "$ICONSET/icon_128x128@2x.png"
cp "$ICONSET/icon_128x128@2x.png" "$ICONSET/icon_256x256.png"
render_png 512 "$ICONSET/icon_256x256@2x.png"
cp "$ICONSET/icon_256x256@2x.png" "$ICONSET/icon_512x512.png"
render_png 1024 "$ICONSET/icon_512x512@2x.png"

iconutil -c icns "$ICONSET" -o "$OUTPUT"
echo "Built $OUTPUT"
