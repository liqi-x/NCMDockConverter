#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_PNG="${1:-$ROOT_DIR/assets/AppIcon-1024.png}"
ICONSET_DIR="$ROOT_DIR/assets/AppIcon.iconset"
OUTPUT_ICNS="$ROOT_DIR/assets/AppIcon.icns"

if [[ ! -f "$SOURCE_PNG" ]]; then
  echo "Source PNG not found: $SOURCE_PNG"
  echo "Usage: ./scripts/make_icns.sh /absolute/path/to/1024x1024.png"
  exit 1
fi

if ! command -v sips >/dev/null 2>&1; then
  echo "sips command not found. This script must run on macOS."
  exit 1
fi

if ! command -v iconutil >/dev/null 2>&1; then
  echo "iconutil command not found. Install Xcode Command Line Tools."
  exit 1
fi

rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

sips -z 16 16     "$SOURCE_PNG" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
sips -z 32 32     "$SOURCE_PNG" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
sips -z 32 32     "$SOURCE_PNG" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
sips -z 64 64     "$SOURCE_PNG" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
sips -z 128 128   "$SOURCE_PNG" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
sips -z 256 256   "$SOURCE_PNG" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
sips -z 256 256   "$SOURCE_PNG" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
sips -z 512 512   "$SOURCE_PNG" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
sips -z 512 512   "$SOURCE_PNG" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
cp "$SOURCE_PNG" "$ICONSET_DIR/icon_512x512@2x.png"

iconutil -c icns "$ICONSET_DIR" -o "$OUTPUT_ICNS"

echo "Generated icon: $OUTPUT_ICNS"
