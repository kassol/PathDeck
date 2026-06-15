import AppKit

/// Finder Services 处理器。`@objc` 方法名即 `Info.plist` 中各 `NSServices` item 的 `NSMessage`，
/// 由系统在主线程从选中项的 `NSPasteboard` 投递 file URL，转为 ``AppRouter/Route`` 路由。
///
/// 路由计算抽到 ``route(for:pasteboard:)`` 以便单测（pasteboard → Route 可验证，菜单呈现不可）。
final class ServicesProvider: NSObject {
    enum Kind {
        case open        // 文件夹 → 导航
        case reveal      // 单项 → 父目录高亮
        case selection   // 多选 → 首项父目录高亮
        case terminal    // 文件夹 → 新建终端
    }

    @objc func openInPathDeck(_ pasteboard: NSPasteboard, userData: String?,
                              error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        dispatch(.open, pasteboard)
    }

    @objc func revealInPathDeck(_ pasteboard: NSPasteboard, userData: String?,
                                error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        dispatch(.reveal, pasteboard)
    }

    @objc func openSelectionInPathDeck(_ pasteboard: NSPasteboard, userData: String?,
                                       error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        dispatch(.selection, pasteboard)
    }

    @objc func openTerminalHereInPathDeck(_ pasteboard: NSPasteboard, userData: String?,
                                          error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        dispatch(.terminal, pasteboard)
    }

    private func dispatch(_ kind: Kind, _ pasteboard: NSPasteboard) {
        guard let route = Self.route(for: kind, pasteboard: pasteboard) else { return }
        AppRouter.shared.request(route)
    }

    static func route(for kind: Kind, pasteboard: NSPasteboard) -> AppRouter.Route? {
        switch kind {
        case .open:
            return firstFolder(in: pasteboard).map { .open($0) }
        case .reveal:
            return firstItem(in: pasteboard).map { .reveal([$0]) }
        case .selection:
            let items = urls(in: pasteboard)
            return items.isEmpty ? nil : .reveal(items)
        case .terminal:
            // Finder 右键「Open Terminal Here」是用户主动操作，可信，无需二次确认
            return firstFolder(in: pasteboard).map { .terminal($0, requireConfirmation: false) }
        }
    }

    private static func firstItem(in pasteboard: NSPasteboard) -> URL? {
        urls(in: pasteboard).first
    }

    private static func firstFolder(in pasteboard: NSPasteboard) -> URL? {
        urls(in: pasteboard).first { isDirectory($0) }
    }

    private static func urls(in pasteboard: NSPasteboard) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let objects = pasteboard.readObjects(forClasses: [NSURL.self], options: options) ?? []
        return objects.compactMap { ($0 as? URL)?.standardizedFileURL }
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(
            atPath: url.path(percentEncoded: false), isDirectory: &isDir
        ) && isDir.boolValue
    }
}
