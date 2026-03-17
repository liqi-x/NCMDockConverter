# NCMDockConverter (macOS)

一个可放在 Dock 运行的 macOS 小工具，**主打双击直接转换**：

- 在 Finder 中双击 `.ncm`（或右键“打开方式”选择 NCMDockConverter），即可静默转换
- 不弹主界面，直接在原目录输出音频文件
- 转换完成自动退出

同时也支持把 `.ncm` 拖入窗口或拖到 Dock 图标转换。

基于文档与工具：<https://github.com/taurusxin/ncmdump>

## 功能

- **双击/打开方式直接转换（优先能力）**：在 Finder 中直接打开 `.ncm` 即可开始转换
- 拖拽一个或多个 `.ncm` 文件到窗口
- 把 `.ncm` 文件直接拖到 Dock 里的应用图标
- 逐个调用 `ncmdump <file.ncm>`
- 输出文件保留在原目录（由 `ncmdump` 默认行为决定）
- 窗口中显示实时日志

## 依赖

- macOS 13+
- Xcode 15+（或带 Swift 6 工具链）
- `ncmdump` 可执行文件（任选其一）
  - `brew install ncmdump`
  - 或手动下载 release 二进制
- （可选）`ffmpeg`，当输入实际解密为 flac 时自动转 mp3
  - `brew install ffmpeg`

## 构建并打包 `.app`

```bash
cd /Users/liqi/Documents/Playground/NCMDockConverter
./scripts/make_app.sh
```

输出路径：

`/Users/liqi/Documents/Playground/NCMDockConverter/dist/NCMDockConverter.app`
`/Users/liqi/Documents/Playground/NCMDockConverter/dist/NCMDockConverter-unsigned.zip`

## 封装 `.dmg`

```bash
cd /Users/liqi/Documents/Playground/NCMDockConverter
./scripts/make_dmg.sh
```

输出路径：

`/Users/liqi/Documents/Playground/NCMDockConverter/dist/NCMDockConverter-unsigned.dmg`

DMG 内会包含：

- `NCMDockConverter.app`
- `Applications` 快捷方式
- `损坏修复(输入密码并回车).command`（输入密码后自动去隔离并打开应用）

图形化安装界面（可选）：

- 将背景图放到 `assets/DMGBackground.png`
- 重新执行 `./scripts/make_dmg.sh`
- 脚本会自动设置窗口背景、图标大小和拖拽位置（App 左侧 -> Applications 右侧）

支持的环境变量：

- `APP_BUNDLE_ID`（默认 `com.liqi.NCMDockConverter`）
- `APP_VERSION`（默认 `1.0`）
- `APP_BUILD`（默认 `1`）

## 应用图标 `.icns`

1. 准备 1024x1024 PNG，放到：`assets/AppIcon-1024.png`
2. 生成 `.icns`：

```bash
cd /Users/liqi/Documents/Playground/NCMDockConverter
./scripts/make_icns.sh
```

生成后得到：`assets/AppIcon.icns`，`make_app.sh` 会自动把它打进 `.app`。

## 签名与公证

脚本：`scripts/sign_and_notarize.sh`

必填环境变量：

- `APP_BUNDLE_ID` 例如 `com.yourname.NCMDockConverter`
- `DEVELOPER_ID_APPLICATION` 例如 `Developer ID Application: Your Name (TEAMID)`
- `APPLE_TEAM_ID` 例如 `ABCDE12345`

认证方式二选一：

- 推荐：`NOTARY_PROFILE`（`xcrun notarytool store-credentials` 保存后的 profile 名称）
- 或：`APPLE_ID` + `APP_SPECIFIC_PASSWORD`

执行示例：

```bash
cd /Users/liqi/Documents/Playground/NCMDockConverter
APP_BUNDLE_ID="com.yourname.NCMDockConverter" \
DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (ABCDE12345)" \
APPLE_TEAM_ID="ABCDE12345" \
NOTARY_PROFILE="AC_NOTARY" \
./scripts/sign_and_notarize.sh
```

脚本会自动执行：

1. 重新构建 `.app`
2. 对可执行文件和 app 签名
3. `notarytool submit --wait`
4. `stapler staple` + `stapler validate`

并生成可分发文件：

- `/Users/liqi/Documents/Playground/NCMDockConverter/dist/NCMDockConverter-notarized.zip`

## 运行

双击 `dist/NCMDockConverter.app` 即可；应用会出现在 Dock。

## 最快使用方式（推荐）

1. 安装后，在 Finder 中找到 `.ncm` 文件
2. 直接双击（或右键 -> 打开方式 -> `NCMDockConverter`）
3. 自动静默转换，输出写回原目录

## 分享给其他电脑（重要）

- 请优先分享 zip 文件，不要直接把 `.app` 拖进聊天工具发送
- 或分享 dmg 文件：`dist/NCMDockConverter-unsigned.dmg`
- 无签名版本分享：`dist/NCMDockConverter-unsigned.zip`
- 签名公证版本分享：`dist/NCMDockConverter-notarized.zip`（推荐）

无开发者账号时（重要）：

- `make_app.sh` 会执行本地 ad-hoc 签名（`codesign -`）并清理隔离属性，以降低“已损坏”概率
- 但不同 macOS 版本策略不同，仍不能替代 Developer ID 公证
- 若接收方仍出现“已损坏且无仍要打开”，通常只能在接收方机器执行 `xattr` 清理，或改用开发者签名+公证版本

若接收方仍提示“已损坏”，可在接收方机器执行：

```bash
xattr -dr com.apple.quarantine /path/to/NCMDockConverter.app
```

启动行为：

- 手动双击启动：显示主界面
- 双击 `.ncm` / 用“打开方式”唤起 / 拖 `.ncm` 到 Dock 图标：后台静默转换，不弹主界面；完成后自动退出

静默模式日志文件：

- `~/Library/Logs/NCMDockConverter.log`

## Dock 拖拽排障

如果“拖到 Dock 图标”仍无反应，请按顺序做：

1. 删除旧的 Dock 图标（右键图标 -> 选项 -> 从 Dock 中移除）
2. 用新构建产物替换旧 app：`dist/NCMDockConverter.app`
3. 双击新 app 启动一次，再把它重新固定到 Dock
4. 再次把 `.ncm` 拖到 Dock 图标测试

原因是 macOS 会缓存应用的文件类型声明，旧缓存可能还指向旧构建。

## 备注

- 当前实现依赖外部 `ncmdump`，不会内置解密算法。
- 转换后是否为 mp3 或 flac 由源文件内容决定（与 `ncmdump` 一致）。
