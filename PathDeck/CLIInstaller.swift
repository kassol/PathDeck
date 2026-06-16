import AppKit

enum CLIInstaller {
    private static let installPath = "/usr/local/bin/pathdeck"

    static func install() {
        guard let source = Bundle.main.url(forResource: "pathdeck", withExtension: nil) else {
            showAlert(
                style: .critical,
                message: "未找到命令行工具",
                info: "App bundle 中缺少 pathdeck 二进制文件。请重新构建 PathDeck。"
            )
            return
        }

        let fm = FileManager.default
        let destDir = "/usr/local/bin"
        let destURL = URL(fileURLWithPath: installPath)
        let srcPath = source.path(percentEncoded: false)

        do {
            if !fm.fileExists(atPath: destDir) {
                try fm.createDirectory(atPath: destDir, withIntermediateDirectories: true)
            }

            var isDir: ObjCBool = false
            if fm.fileExists(atPath: installPath, isDirectory: &isDir), isDir.boolValue {
                showAlert(
                    style: .critical,
                    message: "安装失败",
                    info: "\(installPath) 是一个目录，无法覆盖。请手动删除后重试。"
                )
                return
            }

            let tmpURL = destURL.deletingLastPathComponent()
                .appendingPathComponent(".pathdeck-install-\(UUID().uuidString)")
            try fm.copyItem(atPath: srcPath, toPath: tmpURL.path(percentEncoded: false))
            try fm.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: tmpURL.path(percentEncoded: false)
            )
            _ = try fm.replaceItemAt(destURL, withItemAt: tmpURL)

            showAlert(
                style: .informational,
                message: "命令行工具已安装",
                info: "已安装到 \(installPath)。在终端中输入 pathdeck 即可使用。"
            )
        } catch {
            let escaped = ShellEscape.escape(srcPath)
            showAlert(
                style: .critical,
                message: "安装失败",
                info: "无法写入 \(installPath)。\n请在终端执行：\nsudo cp \(escaped) \(installPath) && sudo chmod 755 \(installPath)"
            )
        }
    }

    private static func showAlert(style: NSAlert.Style, message: String, info: String) {
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = message
        alert.informativeText = info
        alert.runModal()
    }
}
