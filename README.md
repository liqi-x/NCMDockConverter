# NCMConverter (macOS)

一个用于网易云 `.ncm` 转换的 macOS 工具，核心是 **双击直接转换**。

## 功能

- 在 Finder 中双击 `.ncm`（或“打开方式 -> NCMConverter”）即可静默转换
- 把 `.ncm` 拖到 Dock 图标可静默转换
- 把 `.ncm` 拖到应用窗口可查看实时日志
- 可选设置：当源流是 FLAC 时强制输出 MP3
- 附加能力：可直接拖入 `.flac` 转换为 `.mp3`
- 输出文件默认写回原文件目录

基于项目：[taurusxin/ncmdump](https://github.com/taurusxin/ncmdump)

## 快速开始

1. 构建应用：

```bash
./scripts/make_app.sh
```

2. 构建 DMG：

```bash
./scripts/make_dmg.sh
```

3. 输出产物：
- `dist/NCMConverter.app`
- `dist/NCMConverter-unsigned.zip`
- `dist/NCMConverter-unsigned.dmg`
- 可选重命名（用于发布）：`dist/NCMConverter-vX.Y.Z.zip/.dmg`

## 应用行为

- 手动启动应用：显示主界面
- 双击 `.ncm` / 打开方式 / Dock 拖拽：后台静默转换，完成后自动退出
- 静默日志路径：`~/Library/Logs/NCMConverter.log`

## 在其他电脑中打开

- 建议分享：`dist/NCMConverter-unsigned.dmg` 或 `dist/NCMConverter-unsigned.zip`
- 若未使用 Developer ID 公证，不同 macOS 版本的 Gatekeeper 行为会不同
- 若目标电脑提示“已损坏”，可执行：

```bash
xattr -dr com.apple.quarantine /Applications/NCMConverter.app
```

- DMG 内置辅助脚本：`损坏修复(输入密码并回车).command`

## GitHub 发布

仓库已内置 GitHub Actions 工作流：`.github/workflows/release.yml`

- 触发方式：推送 `v*` 标签
- 发布产物：
  - `NCMConverter-vX.Y.Z.zip`
  - `NCMConverter-vX.Y.Z.dmg`

示例：

```bash
git tag v1.0.1
git push origin v1.0.1
```

### 上传本地编译产物到 Release（推荐用于保留 DMG 背景）

当你希望 Release 使用**本地精调 DMG（含背景图）**时：

```bash
./scripts/make_dmg.sh
./scripts/upload_local_release_assets.sh v1.0.1
```

说明：
- 脚本会把本地 `dist/NCMConverter-unsigned.zip/.dmg` 复制为 `dist/NCMConverter-v1.0.1.zip/.dmg`
- 然后上传到对应 tag 的 Release，并覆盖同名旧文件（`--clobber`）
- 依赖 `gh`：`brew install gh && gh auth login`

## 开发环境要求

- macOS 13+
- Xcode 15+（Swift 6 工具链）
- 可用 `ncmdump` 二进制（从 `assets/` 打包或本机安装）
- 可选：`ffmpeg`（用于 FLAC -> MP3）
