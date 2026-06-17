import AppKit

enum CLIInstaller {
    private static let installPath = "/usr/local/bin/pathdeck"

    static func install() {
        guard let source = Bundle.main.url(forResource: "pathdeck", withExtension: nil) else {
            showAlert(
                style: .critical,
                message: String(localized: "Command line tool not found"),
                info: String(localized: "The pathdeck binary is missing from the app bundle. Please rebuild PathDeck.")
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
                    message: String(localized: "Installation failed"),
                    info: String(localized: "\(installPath) is a directory and cannot be overwritten. Please remove it manually and try again.")
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
                message: String(localized: "Command line tool installed"),
                info: String(localized: "Installed to \(installPath). Type pathdeck in Terminal to use it.")
            )
        } catch {
            let escaped = ShellEscape.escape(srcPath)
            showAlert(
                style: .critical,
                message: String(localized: "Installation failed"),
                info: String(localized: "Cannot write to \(installPath).\nPlease run in Terminal:\nsudo cp \(escaped) \(installPath) && sudo chmod 755 \(installPath)")
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
