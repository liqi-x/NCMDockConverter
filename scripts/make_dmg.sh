#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="NCMDockConverter"
APP_PATH="$ROOT_DIR/dist/$APP_NAME.app"
DMG_PATH="$ROOT_DIR/dist/$APP_NAME-unsigned.dmg"
RW_DMG_PATH="$ROOT_DIR/dist/$APP_NAME-tmp.dmg"
STAGE_DIR="$ROOT_DIR/dist/.dmg-staging"
MOUNT_POINT="$ROOT_DIR/dist/.dmg-mount"
VOL_NAME="$APP_NAME"
BACKGROUND_SRC="$ROOT_DIR/assets/DMGBackground.png"
BACKGROUND_DIR_NAME=".background"
BACKGROUND_FILE_NAME="DMGBackground.png"

# Finder window/layout config (tuned for 2550x1700 background artwork)
WIN_LEFT=260
WIN_TOP=140
# Default window width = 560 px
WIN_RIGHT=855
WIN_BOTTOM=644
ICON_SIZE=120
TEXT_SIZE=13
ROW_BASE_Y=202
# Three icons are laid out from left to right and centered in the window.
ROW_GAP=150
WIN_WIDTH=$((WIN_RIGHT - WIN_LEFT))
ROW_CENTER_X=$((WIN_WIDTH / 2))
APP_BASE_X=$((ROW_CENTER_X - ROW_GAP))
APPS_BASE_X=$ROW_CENTER_X
FIX_BASE_X=$((ROW_CENTER_X + ROW_GAP))
ICON_OFFSET_X=0
ICON_OFFSET_Y=-30
APP_POS_X=$((APP_BASE_X + ICON_OFFSET_X))
APP_POS_Y=$((ROW_BASE_Y + ICON_OFFSET_Y))
APPS_POS_X=$((APPS_BASE_X + ICON_OFFSET_X))
APPS_POS_Y=$((ROW_BASE_Y + ICON_OFFSET_Y))
FIX_POS_X=$((FIX_BASE_X + ICON_OFFSET_X))
FIX_POS_Y=$((ROW_BASE_Y + ICON_OFFSET_Y))

"$ROOT_DIR/scripts/make_app.sh"

if [[ ! -d "$APP_PATH" ]]; then
  echo "App not found: $APP_PATH"
  exit 1
fi

rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"
cp -R "$APP_PATH" "$STAGE_DIR/$APP_NAME.app"
ln -s /Applications "$STAGE_DIR/Applications"
cat > "$STAGE_DIR/Install_and_Open.command" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

APP_NAME="NCMDockConverter.app"
TARGET_APP="/Applications/$APP_NAME"
SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_APP="$SOURCE_DIR/$APP_NAME"

echo "NCMDockConverter installer helper"
echo

if [[ ! -d "$TARGET_APP" ]]; then
  echo "App not found in /Applications."
  if [[ -d "$SOURCE_APP" ]]; then
    echo "Copying app to /Applications (requires password)..."
    sudo cp -R "$SOURCE_APP" "/Applications/"
  else
    echo "Cannot find app in dmg folder: $SOURCE_APP"
    exit 1
  fi
fi

echo "Removing quarantine attribute (requires password)..."
sudo xattr -rd com.apple.quarantine "$TARGET_APP"

echo "Opening app..."
open "$TARGET_APP"

echo "Done."
SCRIPT
mv "$STAGE_DIR/Install_and_Open.command" "$STAGE_DIR/损坏修复(输入密码并回车).command"
chmod +x "$STAGE_DIR/损坏修复(输入密码并回车).command"

if [[ -f "$BACKGROUND_SRC" ]]; then
  if command -v sips >/dev/null 2>&1; then
    BG_W="$(sips -g pixelWidth "$BACKGROUND_SRC" 2>/dev/null | awk '/pixelWidth/ {print $2}')"
    BG_H="$(sips -g pixelHeight "$BACKGROUND_SRC" 2>/dev/null | awk '/pixelHeight/ {print $2}')"
    if [[ "$BG_W" != "2550" || "$BG_H" != "1700" ]]; then
      echo "Warning: DMGBackground.png is ${BG_W}x${BG_H}, recommended 2550x1700 for current layout."
    fi
  fi
  echo "Using DMG background: $BACKGROUND_SRC"
else
  echo "DMG background not found at $BACKGROUND_SRC (will use default Finder background)."
fi

# Clear quarantine flags in staging before packaging.
if command -v xattr >/dev/null 2>&1; then
  xattr -dr com.apple.quarantine "$STAGE_DIR" >/dev/null 2>&1 || true
fi

rm -f "$DMG_PATH"
rm -f "$RW_DMG_PATH"
hdiutil create \
  -volname "$VOL_NAME" \
  -srcfolder "$STAGE_DIR" \
  -fs HFS+ \
  -format UDRW \
  -ov \
  "$RW_DMG_PATH"

rm -rf "$MOUNT_POINT"
mkdir -p "$MOUNT_POINT"
ATTACH_OUTPUT="$(hdiutil attach -readwrite -noverify -noautoopen -mountpoint "$MOUNT_POINT" "$RW_DMG_PATH")"
DEVICE="$(printf '%s\n' "$ATTACH_OUTPUT" | awk '/^\/dev\// {print $1; exit}')"

if [[ -z "${DEVICE:-}" || -z "${MOUNT_POINT:-}" ]]; then
  echo "Failed to attach dmg or resolve mount point."
  echo "$ATTACH_OUTPUT"
  exit 1
fi

if [[ -n "$DEVICE" ]]; then
  if [[ -n "${MOUNT_POINT:-}" ]] && [[ -f "$BACKGROUND_SRC" ]] && command -v osascript >/dev/null 2>&1; then
    BG_IN_MOUNT="$MOUNT_POINT/$BACKGROUND_DIR_NAME/$BACKGROUND_FILE_NAME"
    mkdir -p "$MOUNT_POINT/$BACKGROUND_DIR_NAME"
    cp "$BACKGROUND_SRC" "$BG_IN_MOUNT"

    if ! osascript <<OSA
on run
  set mountAlias to POSIX file "$MOUNT_POINT" as alias
  tell application "Finder"
    open mountAlias
    delay 1.0

    set theWindow to missing value
    repeat with w in Finder windows
      try
        if (target of w as alias) is mountAlias then
          set theWindow to w
          exit repeat
        end if
      end try
    end repeat
    if theWindow is missing value then
      set theWindow to front Finder window
    end if

    set current view of theWindow to icon view
    set toolbar visible of theWindow to false
    set statusbar visible of theWindow to false
    set bounds of theWindow to {$WIN_LEFT, $WIN_TOP, $WIN_RIGHT, $WIN_BOTTOM}

    set viewOpts to icon view options of theWindow
    set arrangement of viewOpts to not arranged
    set icon size of viewOpts to $ICON_SIZE
    set text size of viewOpts to $TEXT_SIZE

    set position of item "$APP_NAME.app" of theWindow to {$APP_POS_X, $APP_POS_Y}
    set position of item "Applications" of theWindow to {$APPS_POS_X, $APPS_POS_Y}
    set position of item "损坏修复(输入密码并回车).command" of theWindow to {$FIX_POS_X, $FIX_POS_Y}

    set background picture of viewOpts to POSIX file "$BG_IN_MOUNT"
    update without registering applications
    delay 1.2
    close theWindow
  end tell
end run
OSA
    then
      echo "Applied graphical Finder layout."
    else
      echo "Warning: failed to apply graphical Finder layout, continue building plain dmg."
    fi
  fi

  if [[ -n "${MOUNT_POINT:-}" ]] && command -v bless >/dev/null 2>&1; then
    bless --folder "$MOUNT_POINT" --openfolder "$MOUNT_POINT" >/dev/null 2>&1 || true
  fi

  sync
  hdiutil detach "$DEVICE"
fi

hdiutil convert "$RW_DMG_PATH" -format UDZO -imagekey zlib-level=9 -ov -o "$DMG_PATH"

rm -rf "$STAGE_DIR"
rm -f "$RW_DMG_PATH"
rm -rf "$MOUNT_POINT"

echo "Unsigned distribution dmg: $DMG_PATH"
