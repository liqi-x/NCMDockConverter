#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="NCMDockConverter"
APP_PATH="$ROOT_DIR/dist/$APP_NAME.app"
ZIP_PATH="$ROOT_DIR/dist/$APP_NAME-notarize.zip"
FINAL_ZIP_PATH="$ROOT_DIR/dist/$APP_NAME-notarized.zip"

# Required env vars:
#   APP_BUNDLE_ID                e.g. com.yourname.NCMDockConverter
#   DEVELOPER_ID_APPLICATION     e.g. Developer ID Application: Your Name (TEAMID)
#   APPLE_TEAM_ID                e.g. ABCDE12345
# Auth mode 1 (recommended):
#   NOTARY_PROFILE               keychain profile created by notarytool store-credentials
# Auth mode 2:
#   APPLE_ID and APP_SPECIFIC_PASSWORD

if [[ -z "${APP_BUNDLE_ID:-}" ]]; then
  echo "APP_BUNDLE_ID is required."
  exit 1
fi

if [[ -z "${DEVELOPER_ID_APPLICATION:-}" ]]; then
  echo "DEVELOPER_ID_APPLICATION is required."
  exit 1
fi

if [[ -z "${APPLE_TEAM_ID:-}" ]]; then
  echo "APPLE_TEAM_ID is required."
  exit 1
fi

if [[ -z "${NOTARY_PROFILE:-}" ]]; then
  if [[ -z "${APPLE_ID:-}" || -z "${APP_SPECIFIC_PASSWORD:-}" ]]; then
    echo "Set NOTARY_PROFILE, or set both APPLE_ID and APP_SPECIFIC_PASSWORD."
    exit 1
  fi
fi

"$ROOT_DIR/scripts/make_app.sh"

if [[ ! -d "$APP_PATH" ]]; then
  echo "App not found: $APP_PATH"
  exit 1
fi

if command -v xattr >/dev/null 2>&1; then
  xattr -dr com.apple.quarantine "$APP_PATH" >/dev/null 2>&1 || true
fi

echo "Signing nested binaries..."
if [[ -d "$APP_PATH/Contents/Resources/bin" ]]; then
  while IFS= read -r -d '' bin; do
    codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID_APPLICATION" "$bin"
  done < <(find "$APP_PATH/Contents/Resources/bin" -type f -perm -111 -print0)
fi

echo "Signing app bundle..."
codesign --force --deep --options runtime --timestamp --sign "$DEVELOPER_ID_APPLICATION" "$APP_PATH"

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
spctl --assess --type execute --verbose "$APP_PATH"

echo "Creating zip for notarization..."
rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

echo "Submitting for notarization..."
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "$ZIP_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --team-id "$APPLE_TEAM_ID" \
    --wait
else
  xcrun notarytool submit "$ZIP_PATH" \
    --apple-id "$APPLE_ID" \
    --password "$APP_SPECIFIC_PASSWORD" \
    --team-id "$APPLE_TEAM_ID" \
    --wait
fi

echo "Stapling ticket..."
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"

echo "Creating notarized distribution zip..."
rm -f "$FINAL_ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$FINAL_ZIP_PATH"

echo "All done: signed + notarized app at $APP_PATH"
echo "Notarized distribution zip: $FINAL_ZIP_PATH"
