# NCMConverter (macOS)

A macOS app for NetEase `.ncm` conversion, focused on **double-click direct conversion**.

## Features

- Double-click `.ncm` in Finder (or use **Open With -> NCMConverter**) to convert silently
- Drag `.ncm` onto Dock icon for silent conversion
- Drag `.ncm` into app window for visible log mode
- Optional setting: force output to MP3 when source stream is FLAC
- Extra utility: drop `.flac` to convert directly to `.mp3`
- Output files are written in the original file directory

Based on: [taurusxin/ncmdump](https://github.com/taurusxin/ncmdump)

## Quick Start

1. Build app:

```bash
./scripts/make_app.sh
```

2. Build DMG:

```bash
./scripts/make_dmg.sh
```

3. Output artifacts:
- `dist/NCMConverter.app`
- `dist/NCMConverter-unsigned.zip`
- `dist/NCMConverter-unsigned.dmg`

## In-App Behavior

- Launch app manually: shows main window
- Open `.ncm` by double-click / Open With / Dock drop: runs silently and exits after conversion
- Silent log file: `~/Library/Logs/NCMConverter.log`

## 在其他电脑中打开

- Recommended: share `dist/NCMConverter-unsigned.dmg` or `dist/NCMConverter-unsigned.zip`
- Without Developer ID notarization, Gatekeeper behavior may vary by macOS version
- If target Mac shows “damaged”, run:

```bash
xattr -dr com.apple.quarantine /Applications/NCMConverter.app
```

- DMG includes helper script: `损坏修复(输入密码并回车).command`

## Release (GitHub)

This repo includes GitHub Actions workflow: `.github/workflows/release.yml`

- Trigger: push tag `v*`
- Output assets:
  - `NCMConverter-unsigned.zip`
  - `NCMConverter-unsigned.dmg`

Example:

```bash
git tag v1.0.1
git push origin v1.0.1
```

## Development Requirements

- macOS 13+
- Xcode 15+ (Swift 6 toolchain)
- `ncmdump` binary available (bundled from `assets/` or local install)
- Optional: `ffmpeg` for FLAC->MP3 conversion

## Signing & Notarization (Optional)

Use:

```bash
./scripts/sign_and_notarize.sh
```

You need Apple Developer credentials and notarization configuration.
