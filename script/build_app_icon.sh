#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_ICON="$PROJECT_ROOT/Assets/AppIcon/app-icon-1024.png"
OUTPUT_ICON="$PROJECT_ROOT/Assets/AppIcon/AppIcon.icns"
ICON_TEMP_ROOT="$(mktemp -d)"
ICONSET="$ICON_TEMP_ROOT/AppIcon.iconset"

trap 'rm -rf "$ICON_TEMP_ROOT"' EXIT

if [[ ! -f "$SOURCE_ICON" ]]; then
  echo "Missing app icon master: $SOURCE_ICON" >&2
  exit 1
fi

mkdir -p "$ICONSET"

render_icon() {
  local pixels="$1"
  local filename="$2"
  sips -z "$pixels" "$pixels" "$SOURCE_ICON" --out "$ICONSET/$filename" >/dev/null
}

render_icon 16 icon_16x16.png
render_icon 32 icon_16x16@2x.png
render_icon 32 icon_32x32.png
render_icon 64 icon_32x32@2x.png
render_icon 128 icon_128x128.png
render_icon 256 icon_128x128@2x.png
render_icon 256 icon_256x256.png
render_icon 512 icon_256x256@2x.png
render_icon 512 icon_512x512.png
render_icon 1024 icon_512x512@2x.png

iconutil -c icns "$ICONSET" -o "$OUTPUT_ICON"
echo "Built $OUTPUT_ICON"
