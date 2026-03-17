#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPO="${REPO:-liqi-x/NCMConverter}"
TAG="${1:-}"

if [[ -z "$TAG" ]]; then
  echo "Usage: $0 <tag>  (example: $0 v1.0.0)"
  exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "GitHub CLI (gh) is required. Install first: brew install gh"
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "Please login first: gh auth login"
  exit 1
fi

ZIP_PATH="$ROOT_DIR/dist/NCMConverter-${TAG}.zip"
DMG_PATH="$ROOT_DIR/dist/NCMConverter-${TAG}.dmg"
LEGACY_ZIP="$ROOT_DIR/dist/NCMConverter-unsigned.zip"
LEGACY_DMG="$ROOT_DIR/dist/NCMConverter-unsigned.dmg"

if [[ ! -f "$ZIP_PATH" && -f "$LEGACY_ZIP" ]]; then
  cp "$LEGACY_ZIP" "$ZIP_PATH"
fi
if [[ ! -f "$DMG_PATH" && -f "$LEGACY_DMG" ]]; then
  cp "$LEGACY_DMG" "$DMG_PATH"
fi

if [[ ! -f "$ZIP_PATH" || ! -f "$DMG_PATH" ]]; then
  echo "Release assets not found."
  echo "Expected:"
  echo "  $ZIP_PATH"
  echo "  $DMG_PATH"
  echo "Run ./scripts/make_dmg.sh first."
  exit 1
fi

if ! gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  echo "Release $TAG not found, creating it from existing tag..."
  gh release create "$TAG" --repo "$REPO" --verify-tag --title "$TAG" --notes ""
fi

echo "Uploading assets to release $TAG in $REPO ..."
gh release upload "$TAG" "$ZIP_PATH" "$DMG_PATH" --repo "$REPO" --clobber
echo "Done."
