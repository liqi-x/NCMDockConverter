import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
@main
struct NCMDockConverterApp: App {
    @StateObject private var viewModel = ConverterViewModel.shared
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("NCM 转 MP3", id: "main") {
            ContentView(viewModel: viewModel)
                .frame(minWidth: 504, minHeight: 420)
        }
        .defaultSize(width: 504, height: 550)
        .windowStyle(.hiddenTitleBar)

        Settings {
            SettingsView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var queuedSilentURLs: [URL] = []
    private var silentProcessing = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        localizeMainMenu()
    }

    private func localizeMainMenu() {
        guard let mainMenu = NSApp.mainMenu else { return }
        let menuTitleMap: [String: String] = [
            "File": "文件",
            "Edit": "编辑",
            "View": "视图",
            "Window": "窗口",
            "Help": "帮助"
        ]
        for item in mainMenu.items {
            if let localized = menuTitleMap[item.title] {
                item.title = localized
            }
        }
    }

    private func hideAllWindows() {
        for window in NSApp.windows {
            window.orderOut(nil)
        }
        NSApp.hide(nil)
    }

    private func normalizedFileURLs(from urls: [URL]) -> [URL] {
        var result: [URL] = []
        var seen = Set<String>()

        for url in urls {
            let fileURL: URL
            if url.isFileURL {
                fileURL = url
            } else if let candidate = URL(string: url.absoluteString), candidate.isFileURL {
                fileURL = candidate
            } else {
                continue
            }

            let normalized = fileURL.standardizedFileURL
            let key = normalized.path
            if !key.isEmpty && !seen.contains(key) {
                seen.insert(key)
                result.append(normalized)
            }
        }

        return result
    }

    private func enqueueSilentConversion(_ urls: [URL]) {
        queuedSilentURLs.append(contentsOf: urls)
        ConverterViewModel.shared.appendExternalLog("静默队列入队，当前数量=\(queuedSilentURLs.count)")
        startNextSilentBatchIfNeeded()
    }

    private func startNextSilentBatchIfNeeded() {
        guard !silentProcessing else { return }
        guard !queuedSilentURLs.isEmpty else { return }

        silentProcessing = true
        let batch = queuedSilentURLs
        queuedSilentURLs.removeAll()
        ConverterViewModel.shared.appendExternalLog("静默批次开始，文件数=\(batch.count)")

        ConverterViewModel.shared.convertDroppedItems(
            batch,
            silent: true,
            terminateWhenDone: false
        ) { [weak self] in
            guard let self else { return }
            self.silentProcessing = false
            ConverterViewModel.shared.appendExternalLog("静默批次结束，待处理=\(self.queuedSilentURLs.count)")
            if self.queuedSilentURLs.isEmpty {
                NSApp.terminate(nil)
            } else {
                self.startNextSilentBatchIfNeeded()
            }
        }
    }

    private func dispatchOpen(_ urls: [URL], sender: NSApplication?) {
        let fileURLs = normalizedFileURLs(from: urls)
        guard !fileURLs.isEmpty else {
            sender?.reply(toOpenOrPrint: .failure)
            return
        }

        ConverterViewModel.shared.appendExternalLog("收到静默唤起文件：\(fileURLs.map { $0.path }.joined(separator: " | "))")
        hideAllWindows()
        enqueueSilentConversion(fileURLs)

        sender?.reply(toOpenOrPrint: .success)
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let urls = filenames.map { URL(fileURLWithPath: $0) }
        dispatchOpen(urls, sender: sender)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        dispatchOpen(urls, sender: nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        if let keyWindow = NSApp.windows.first {
            keyWindow.makeKeyAndOrderFront(nil)
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

@MainActor
final class ConverterViewModel: ObservableObject {
    static let shared = ConverterViewModel()

    @Published var isConverting = false
    @Published var logs: [String] = ["将 .ncm 文件拖入窗口即可开始转换（原目录输出）。"]
    private let logFileURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/NCMDockConverter.log")

    func convertDroppedItems(
        _ items: [URL],
        silent: Bool = false,
        terminateWhenDone: Bool = false,
        completion: (@MainActor @Sendable () -> Void)? = nil
    ) {
        appendLog("收到文件：\(items.map { $0.lastPathComponent }.joined(separator: "，"))")
        let ncmFiles = items.filter { $0.pathExtension.lowercased() == "ncm" }
        let flacFiles = items.filter { $0.pathExtension.lowercased() == "flac" }
        let ncmToConvert = ncmFiles.filter { ensureFileAccess($0) }
        let flacToConvert = flacFiles.filter { ensureFileAccess($0) }

        guard !ncmFiles.isEmpty || !flacFiles.isEmpty else {
            appendLog("未发现 .ncm 或 .flac 文件。")
            if terminateWhenDone {
                NSApp.terminate(nil)
            }
            completion?()
            return
        }

        guard !ncmToConvert.isEmpty || !flacToConvert.isEmpty else {
            appendLog("无可转换文件：请检查文件夹读写权限后重试。")
            appendLog("可在“系统设置 -> 隐私与安全性 -> 文件与文件夹”中允许 NCMDockConverter 访问“音乐文件夹”。")
            if terminateWhenDone {
                NSApp.terminate(nil)
            }
            completion?()
            return
        }

        var ncmdumpCommand: URL?
        if !ncmToConvert.isEmpty {
            if let command = resolveNCMDump() {
                ncmdumpCommand = command
                appendLog("使用 ncmdump：\(command.path)")
            } else {
                appendLog("未找到 ncmdump：将跳过 .ncm 转换。")
                if flacToConvert.isEmpty {
                    if terminateWhenDone {
                        NSApp.terminate(nil)
                    }
                    completion?()
                    return
                }
            }
        }

        let ffmpegCommand = resolveFFmpeg()
        if !flacToConvert.isEmpty, ffmpegCommand == nil {
            appendLog("未找到 ffmpeg：将跳过 .flac 转 MP3。")
        }

        if !silent {
            isConverting = true
        }
        Task(priority: .userInitiated) {
            if let command = ncmdumpCommand {
                for fileURL in ncmToConvert {
                    await self.convert(fileURL, using: command)
                }
            }

            if let ffmpegCommand {
                for flacURL in flacToConvert {
                    await self.convertFLACInput(flacURL, using: ffmpegCommand)
                }
            }

            if !silent {
                self.isConverting = false
                self.appendLog("转换完成。")
            }
            if terminateWhenDone {
                NSApp.terminate(nil)
            }
            completion?()
        }
    }

    @MainActor
    func appendExternalLog(_ line: String) {
        appendLog(line)
    }

    @MainActor
    private func appendLog(_ line: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let formatted = "[\(formatter.string(from: Date()))] \(line)"
        logs.append(formatted)

        let text = formatted + "\n"
        if let data = text.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logFileURL.path) {
                if let handle = try? FileHandle(forWritingTo: logFileURL) {
                    do {
                        try handle.seekToEnd()
                        try handle.write(contentsOf: data)
                        try handle.close()
                    } catch {
                        try? handle.close()
                    }
                }
            } else {
                try? data.write(to: logFileURL, options: .atomic)
            }
        }
    }

    private func resolveNCMDump() -> URL? {
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("bin/ncmdump"),
           FileManager.default.isExecutableFile(atPath: bundled.path) {
            return bundled
        }

        let commonPaths = [
            "/opt/homebrew/bin/ncmdump",
            "/usr/local/bin/ncmdump"
        ]

        for path in commonPaths where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }

        return nil
    }

    private func convertFLACInput(_ flacURL: URL, using ffmpegURL: URL) async {
        await MainActor.run {
            appendLog("正在转换 FLAC：\(flacURL.path)")
        }
        let mp3URL = flacURL.deletingPathExtension().appendingPathExtension("mp3")
        let (ok, text) = transcodeFlacToMP3(flacURL: flacURL, mp3URL: mp3URL, ffmpegURL: ffmpegURL)
        await MainActor.run {
            if ok {
                appendLog("FLAC 转 MP3 成功：\(mp3URL.lastPathComponent)")
            } else {
                appendLog("FLAC 转 MP3 失败：\(flacURL.lastPathComponent)")
            }
            if !text.isEmpty {
                appendLog(text)
            }
        }
    }

    private func ensureFileAccess(_ fileURL: URL) -> Bool {
        let fm = FileManager.default
        let folderURL = fileURL.deletingLastPathComponent()
        let folderPath = folderURL.path
        let filePath = fileURL.path

        guard fm.isReadableFile(atPath: filePath) else {
            appendLog("无读取权限：\(filePath)")
            return false
        }

        let probeURL = folderURL.appendingPathComponent(".ncmdockconverter_probe_\(UUID().uuidString)")
        do {
            try "probe".write(to: probeURL, atomically: true, encoding: .utf8)
            try? fm.removeItem(at: probeURL)
            return true
        } catch {
            appendLog("无写入权限：\(folderPath)")
            appendLog("权限检测失败：\(error.localizedDescription)")
            return false
        }
    }

    private func resolveFFmpeg() -> URL? {
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("bin/ffmpeg"),
           FileManager.default.isExecutableFile(atPath: bundled.path) {
            return bundled
        }

        let commonPaths = [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg"
        ]

        for path in commonPaths where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }

        return nil
    }

    private func transcodeFlacToMP3(flacURL: URL, mp3URL: URL, ffmpegURL: URL) -> (Bool, String) {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = ffmpegURL
        process.arguments = [
            "-y",
            "-i", flacURL.path,
            "-codec:a", "libmp3lame",
            "-q:a", "2",
            mp3URL.path
        ]
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()
            let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let error = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let text = [output, error].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            return (process.terminationStatus == 0, text)
        } catch {
            return (false, error.localizedDescription)
        }
    }

    private var forceMP3Output: Bool {
        UserDefaults.standard.bool(forKey: "forceMP3Output")
    }

    private func runtimeLibraryPath() -> String? {
        Bundle.main.resourceURL?.appendingPathComponent("lib").path
    }

    private func convert(_ fileURL: URL, using command: URL) async {
        await MainActor.run {
            appendLog("正在转换：\(fileURL.path)")
        }

        let fm = FileManager.default
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ncmdockconverter-\(UUID().uuidString)", isDirectory: true)
        let stagedInput = tempDir.appendingPathComponent("input.ncm")

        do {
            try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
            try fm.copyItem(at: fileURL, to: stagedInput)
        } catch {
            await MainActor.run {
                appendLog("临时文件准备失败：\(error.localizedDescription)")
            }
            return
        }

        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = command
        process.arguments = [stagedInput.path]
        process.currentDirectoryURL = tempDir
        var env = ProcessInfo.processInfo.environment
        if let runtimeLibraryPath = runtimeLibraryPath() {
            let existing = env["DYLD_LIBRARY_PATH"] ?? ""
            env["DYLD_LIBRARY_PATH"] = existing.isEmpty ? runtimeLibraryPath : "\(runtimeLibraryPath):\(existing)"
            env["DYLD_FALLBACK_LIBRARY_PATH"] = env["DYLD_LIBRARY_PATH"]
            await MainActor.run {
                appendLog("运行时库路径：\(runtimeLibraryPath)")
            }
        }
        process.environment = env
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()

            let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let error = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

            if process.terminationStatus == 0 {
                let baseURL = fileURL.deletingPathExtension()
                let stagedMP3 = tempDir.appendingPathComponent("input.mp3")
                let stagedFLAC = tempDir.appendingPathComponent("input.flac")
                let finalMP3 = baseURL.appendingPathExtension("mp3")
                let finalFLAC = baseURL.appendingPathExtension("flac")

                if fm.fileExists(atPath: stagedMP3.path) {
                    try? fm.removeItem(at: finalMP3)
                    try? fm.moveItem(at: stagedMP3, to: finalMP3)
                }
                if fm.fileExists(atPath: stagedFLAC.path) {
                    try? fm.removeItem(at: finalFLAC)
                    try? fm.moveItem(at: stagedFLAC, to: finalFLAC)
                }

                await MainActor.run {
                    appendLog("转换成功：\(fileURL.lastPathComponent)")
                    if !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        appendLog(output.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                }

                do {
                    var trashedURL: NSURL?
                    try fm.trashItem(at: fileURL, resultingItemURL: &trashedURL)
                    await MainActor.run {
                        appendLog("已移入废纸篓：\(fileURL.lastPathComponent)")
                    }
                } catch {
                    await MainActor.run {
                        appendLog("移入废纸篓失败：\(fileURL.lastPathComponent)（\(error.localizedDescription)）")
                    }
                }

                let mp3URL = baseURL.appendingPathExtension("mp3")
                let flacURL = baseURL.appendingPathExtension("flac")
                if forceMP3Output,
                   !FileManager.default.fileExists(atPath: mp3URL.path),
                   FileManager.default.fileExists(atPath: flacURL.path) {
                    if let ffmpeg = resolveFFmpeg() {
                        let (ok, text) = transcodeFlacToMP3(flacURL: flacURL, mp3URL: mp3URL, ffmpegURL: ffmpeg)
                        await MainActor.run {
                            if ok {
                                appendLog("设置启用：已将 FLAC 转为 MP3：\(mp3URL.lastPathComponent)")
                            } else {
                                appendLog("FLAC 转 MP3 失败：\(flacURL.lastPathComponent)")
                            }
                            if !text.isEmpty {
                                appendLog(text)
                            }
                        }
                        if ok {
                            try? FileManager.default.removeItem(at: flacURL)
                        }
                    } else {
                        await MainActor.run {
                            appendLog("设置启用 MP3 输出，但未找到 ffmpeg。")
                        }
                    }
                }
            } else {
                await MainActor.run {
                    appendLog("转换失败：\(fileURL.lastPathComponent)（退出码 \(process.terminationStatus)）")
                    if !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        appendLog(output.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                    if !error.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        appendLog(error.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                }
            }
        } catch {
            await MainActor.run {
                appendLog("执行错误：\(error.localizedDescription)")
            }
        }

        try? fm.removeItem(at: tempDir)
    }
}

struct ContentView: View {
    @ObservedObject var viewModel: ConverterViewModel
    @State private var isTargeted = false
    @State private var donationLightImage: NSImage? = nil
    @State private var donationDarkImage: NSImage? = nil
    @Environment(\.colorScheme) private var colorScheme

    private final class URLCollector: @unchecked Sendable {
        private var storage: [URL] = []
        private let lock = NSLock()

        func append(_ url: URL) {
            lock.lock()
            storage.append(url)
            lock.unlock()
        }

        func values() -> [URL] {
            lock.lock()
            let snapshot = storage
            lock.unlock()
            return snapshot
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        let group = DispatchGroup()
        let collector = URLCollector()

        for provider in providers where
            provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) ||
            provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            group.enter()
            let typeIdentifier = provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
                ? UTType.fileURL.identifier
                : UTType.url.identifier
            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, _ in
                defer { group.leave() }

                var parsedURL: URL?
                if let data = item as? Data,
                   let string = String(data: data, encoding: .utf8) {
                    parsedURL = URL(string: string)
                } else if let string = item as? String {
                    parsedURL = URL(string: string)
                } else if let nsURL = item as? NSURL {
                    parsedURL = nsURL as URL
                }

                if let parsedURL {
                    collector.append(parsedURL)
                }
            }
        }

        group.notify(queue: .main) {
            let urls = collector.values()
            if !urls.isEmpty {
                viewModel.convertDroppedItems(urls)
            }
        }

        return true
    }

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.width < 760
            VStack(spacing: 16) {
                HStack(alignment: .center, spacing: 18) {
                    headerTexts
                    Spacer(minLength: 16)
                    donationCard(compact: compact)
                }
                .padding(.horizontal, compact ? 6 : 10)
                .padding(.leading, compact ? 8 : 16)

                Text("支持拖拽一个或多个 .ncm 文件到下方区域")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(isTargeted ? Color.accentColor.opacity(0.25) : Color.gray.opacity(0.15))

                    RoundedRectangle(cornerRadius: 16)
                        .stroke(style: StrokeStyle(lineWidth: 2, dash: [8]))
                        .foregroundColor(isTargeted ? Color.accentColor : Color.secondary)

                    VStack(spacing: 10) {
                        Image(systemName: "square.and.arrow.down.on.square")
                            .font(.system(size: 42, weight: .medium))
                        Text(viewModel.isConverting ? "转换中..." : "拖拽 .ncm 文件到这里")
                            .font(.headline)
                    }
                    .foregroundStyle(isTargeted ? Color.accentColor : Color.primary)
                }
                .frame(height: 220)
                .onDrop(of: [UTType.fileURL.identifier, UTType.url.identifier], isTargeted: $isTargeted) { providers in
                    handleDrop(providers: providers)
                }

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(viewModel.logs.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(.body, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
                .padding(10)
                .background(Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            }
            .padding(20)
        }
        .onAppear {
            if donationLightImage == nil {
                donationLightImage = loadResourceImage(named: "DonationQRLight.png")
                    ?? loadResourceImage(named: "DonationQR.png")
            }
            if donationDarkImage == nil {
                donationDarkImage = loadResourceImage(named: "DonationQRDark.png")
                    ?? loadResourceImage(named: "DonationQR.png")
            }
        }
    }

    private func loadResourceImage(named name: String) -> NSImage? {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent(name) else {
            return nil
        }
        return NSImage(contentsOf: url)
    }

    private var activeDonationImage: NSImage? {
        if colorScheme == .dark {
            return donationLightImage ?? donationDarkImage
        }
        return donationDarkImage ?? donationLightImage
    }

    @ViewBuilder
    private var headerTexts: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("NCM 转 MP3")
                .font(.system(size: 30, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            Text("拖入 .ncm 文件，自动在原目录生成音频文件")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .minimumScaleFactor(0.98)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(2)
        }
    }

    @ViewBuilder
    private func donationCard(compact: Bool) -> some View {
        let cardWidth: CGFloat = compact ? 116 : 120
        let cardHeight: CGFloat = compact ? 136 : 140
        let qrSize: CGFloat = compact ? 82 : 84
        let horizontalInset: CGFloat = max(6, min(8, (cardWidth - qrSize) / 2 - 4))
        let verticalInset: CGFloat = max(6, min(8, (cardHeight - qrSize) / 2 - 8))

        VStack(alignment: .center, spacing: 8) {
            Text("感谢捐赠")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            if let donationImage = activeDonationImage {
                Image(nsImage: donationImage)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: qrSize, height: qrSize)
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.gray.opacity(0.12))
                    .frame(width: qrSize, height: qrSize)
                    .overlay(
                        Text("请放入\nDonationQRLight.png\nDonationQRDark.png")
                            .font(.system(size: 11))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    )
            }
        }
        .padding(.horizontal, horizontalInset)
        .padding(.vertical, verticalInset)
        .frame(width: cardWidth, height: cardHeight)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(colorScheme == .dark ? Color.white.opacity(0.09) : Color.white.opacity(0.82))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: colorScheme == .dark ? Color.black.opacity(0.25) : Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
    }
}

struct SettingsView: View {
    @AppStorage("forceMP3Output") private var forceMP3Output = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("转换设置")
                .font(.title3.bold())

            HStack(spacing: 10) {
                Text("强制输出 MP3（FLAC 将自动转为 MP3）")
                Spacer(minLength: 12)
                Toggle("", isOn: $forceMP3Output)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            Text(forceMP3Output ? "已开启：优先输出 MP3。" : "已关闭：保持源格式（源是 FLAC 就输出 FLAC）。")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Spacer(minLength: 6)

            Text("制作 by Nothing_Studio ( bilibili )")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(18)
        .frame(width: 420)
    }
}
