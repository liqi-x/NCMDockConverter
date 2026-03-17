#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="NCMConverter"
APP_BUNDLE_ID="${APP_BUNDLE_ID:-com.liqi.NCMConverter}"
APP_VERSION="${APP_VERSION:-1.0}"
APP_BUILD="${APP_BUILD:-1}"
BUILD_DIR="$ROOT_DIR/.build/release"
APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"
DIST_ZIP="$ROOT_DIR/dist/$APP_NAME-unsigned.zip"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RES_DIR="$CONTENTS_DIR/Resources"
ICON_FILE="$ROOT_DIR/assets/AppIcon.icns"
DONATION_IMAGE="$ROOT_DIR/assets/DonationQR.png"
DONATION_IMAGE_LIGHT="$ROOT_DIR/assets/DonationQRLight.png"
DONATION_IMAGE_DARK="$ROOT_DIR/assets/DonationQRDark.png"
LIB_DIR="$RES_DIR/lib"
LOCAL_NCMDUMP_BIN="$ROOT_DIR/assets/ncmdump"
LOCAL_NCMDUMP_BIN_ARM64="$ROOT_DIR/assets/ncmdump-arm64"
LOCAL_NCMDUMP_BIN_X64="$ROOT_DIR/assets/ncmdump-x86_64"

mkdir -p "$ROOT_DIR/dist"

swift build -c release --package-path "$ROOT_DIR"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RES_DIR/bin" "$LIB_DIR"

cp "$BUILD_DIR/$APP_NAME" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

if [[ -f "$ICON_FILE" ]]; then
  cp "$ICON_FILE" "$RES_DIR/AppIcon.icns"
fi

if [[ -f "$DONATION_IMAGE" ]]; then
  cp "$DONATION_IMAGE" "$RES_DIR/DonationQR.png"
fi
if [[ -f "$DONATION_IMAGE_LIGHT" ]]; then
  cp "$DONATION_IMAGE_LIGHT" "$RES_DIR/DonationQRLight.png"
fi
if [[ -f "$DONATION_IMAGE_DARK" ]]; then
  cp "$DONATION_IMAGE_DARK" "$RES_DIR/DonationQRDark.png"
fi

# Prefer manually provided official release binary first.
if [[ -x "$LOCAL_NCMDUMP_BIN" ]]; then
  cp "$LOCAL_NCMDUMP_BIN" "$RES_DIR/bin/ncmdump"
elif [[ -x "$LOCAL_NCMDUMP_BIN_ARM64" ]]; then
  cp "$LOCAL_NCMDUMP_BIN_ARM64" "$RES_DIR/bin/ncmdump"
elif [[ -x "$LOCAL_NCMDUMP_BIN_X64" ]]; then
  cp "$LOCAL_NCMDUMP_BIN_X64" "$RES_DIR/bin/ncmdump"
elif [[ -x "/opt/homebrew/bin/ncmdump" ]]; then
  cp "/opt/homebrew/bin/ncmdump" "$RES_DIR/bin/ncmdump"
elif [[ -x "/usr/local/bin/ncmdump" ]]; then
  cp "/usr/local/bin/ncmdump" "$RES_DIR/bin/ncmdump"
fi

if [[ -x "/opt/homebrew/bin/ffmpeg" ]]; then
  cp "/opt/homebrew/bin/ffmpeg" "$RES_DIR/bin/ffmpeg"
elif [[ -x "/usr/local/bin/ffmpeg" ]]; then
  cp "/usr/local/bin/ffmpeg" "$RES_DIR/bin/ffmpeg"
fi

bundle_macos_deps() {
  local target="$1"
  local dep
  local dep_base
  local copied="$LIB_DIR/.copied_deps.txt"
  touch "$copied"

  while read -r dep _; do
    [[ -z "$dep" ]] && continue
    [[ "$dep" == "$target" ]] && continue
    case "$dep" in
      /System/*|/usr/lib/*|/System/Volumes/*|@*)
        continue
        ;;
    esac
    [[ -f "$dep" ]] || continue

    dep_base="$(basename "$dep")"
    if ! grep -Fqx "$dep" "$copied"; then
      cp "$dep" "$LIB_DIR/$dep_base"
      echo "$dep" >> "$copied"
      bundle_macos_deps "$LIB_DIR/$dep_base"
    fi
  done < <(otool -L "$target" | tail -n +2 | awk '{print $1}')
}

if [[ -x "$RES_DIR/bin/ncmdump" ]] && command -v otool >/dev/null 2>&1 && command -v install_name_tool >/dev/null 2>&1; then
  chmod u+w "$RES_DIR/bin/ncmdump" >/dev/null 2>&1 || true
  bundle_macos_deps "$RES_DIR/bin/ncmdump"
fi

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>zh-Hans</string>
  <key>CFBundleLocalizations</key>
  <array>
    <string>zh-Hans</string>
    <string>en</string>
  </array>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$APP_BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$APP_BUILD</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
PLIST

if [[ -f "$ICON_FILE" ]]; then
cat >> "$CONTENTS_DIR/Info.plist" <<PLIST
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
PLIST
fi

cat >> "$CONTENTS_DIR/Info.plist" <<'PLIST'
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeExtensions</key>
      <array>
        <string>ncm</string>
      </array>
      <key>CFBundleTypeName</key>
      <string>NCM Audio</string>
      <key>CFBundleTypeRole</key>
      <string>Viewer</string>
      <key>LSHandlerRank</key>
      <string>Owner</string>
      <key>LSItemContentTypes</key>
      <array>
        <string>com.liqi.ncm-audio</string>
      </array>
    </dict>
    <dict>
      <key>CFBundleTypeExtensions</key>
      <array>
        <string>flac</string>
      </array>
      <key>CFBundleTypeName</key>
      <string>FLAC Audio</string>
      <key>CFBundleTypeRole</key>
      <string>Viewer</string>
      <key>LSHandlerRank</key>
      <string>Alternate</string>
      <key>LSItemContentTypes</key>
      <array>
        <string>com.liqi.flac-audio</string>
      </array>
    </dict>
  </array>
  <key>UTExportedTypeDeclarations</key>
  <array>
    <dict>
      <key>UTTypeIdentifier</key>
      <string>com.liqi.ncm-audio</string>
      <key>UTTypeDescription</key>
      <string>NCM Audio File</string>
      <key>UTTypeConformsTo</key>
      <array>
        <string>public.data</string>
      </array>
      <key>UTTypeTagSpecification</key>
      <dict>
        <key>public.filename-extension</key>
        <array>
          <string>ncm</string>
        </array>
      </dict>
    </dict>
    <dict>
      <key>UTTypeIdentifier</key>
      <string>com.liqi.flac-audio</string>
      <key>UTTypeDescription</key>
      <string>FLAC Audio File</string>
      <key>UTTypeConformsTo</key>
      <array>
        <string>public.audio</string>
      </array>
      <key>UTTypeTagSpecification</key>
      <dict>
        <key>public.filename-extension</key>
        <array>
          <string>flac</string>
        </array>
        <key>public.mime-type</key>
        <array>
          <string>audio/flac</string>
        </array>
      </dict>
    </dict>
  </array>
PLIST

cat >> "$CONTENTS_DIR/Info.plist" <<'PLIST'
</dict>
</plist>
PLIST

echo "Built app: $APP_DIR"
echo "Bundle ID: $APP_BUNDLE_ID"
if [[ -f "$ICON_FILE" ]]; then
  echo "Bundled icon: $ICON_FILE"
else
  echo "No icon found at $ICON_FILE (skip icon embedding)."
fi
if [[ -f "$DONATION_IMAGE" ]]; then
  echo "Bundled donation image: $DONATION_IMAGE"
fi
if [[ -f "$DONATION_IMAGE_LIGHT" ]]; then
  echo "Bundled donation light image: $DONATION_IMAGE_LIGHT"
fi
if [[ -f "$DONATION_IMAGE_DARK" ]]; then
  echo "Bundled donation dark image: $DONATION_IMAGE_DARK"
fi
if [[ -x "$RES_DIR/bin/ncmdump" ]]; then
  echo "Bundled ncmdump into app resources."
  NCM_VER="$("$RES_DIR/bin/ncmdump" -v 2>/dev/null | head -n 1 || true)"
  if [[ -n "$NCM_VER" ]]; then
    echo "ncmdump version: $NCM_VER"
    if [[ "$NCM_VER" == *"1.2."* ]]; then
      echo "WARNING: ncmdump 1.2.x may fail with UTF-8 filenames. Use official Release >= 1.3.0."
    fi
  fi
else
  echo "ncmdump not bundled. Install it or copy binary to $RES_DIR/bin/ncmdump"
fi
if [[ -x "$RES_DIR/bin/ffmpeg" ]]; then
  echo "Bundled ffmpeg into app resources."
fi

# Ensure metadata/signing operations can update files.
chmod -R u+w "$APP_DIR" >/dev/null 2>&1 || true

# Clear quarantine flags that may be inherited from downloaded binaries/resources.
if command -v xattr >/dev/null 2>&1; then
  xattr -dr com.apple.quarantine "$APP_DIR" >/dev/null 2>&1 || true
fi

# Ad-hoc sign app for better Gatekeeper behavior on other Macs (no developer account needed).
if command -v codesign >/dev/null 2>&1; then
  if [[ -d "$RES_DIR/bin" ]]; then
    while IFS= read -r -d '' bin; do
      codesign --force --sign - "$bin" >/dev/null 2>&1 || true
    done < <(find "$RES_DIR/bin" -type f -perm -111 -print0)
  fi
  codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true
  codesign --verify --deep --strict "$APP_DIR" >/dev/null 2>&1 || true
fi

# Build a transport-safe zip for sharing.
rm -f "$DIST_ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$DIST_ZIP"
echo "Unsigned distribution zip: $DIST_ZIP"
