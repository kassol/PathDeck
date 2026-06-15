import Foundation

/// 解析 `pathdeck://` URL 为 ``AppRouter/Route``，并做安全校验。
///
/// 采用查询参数式 `pathdeck://open?path=/abs`（而非 `pathdeck:///abs`），
/// 由 `URLComponents` 统一 percent-decode，规避空 host + 路径含空格/中文/`#`/`?` 的编码坑。
/// 任何非法输入（scheme 不符 / 未知动作 / 相对路径 / 不存在 / 类型不符）一律返回 nil 静默丢弃。
enum URLSchemeHandler {
    static let scheme = "pathdeck"

    static func route(for url: URL) -> AppRouter.Route? {
        guard url.scheme == scheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let action = components.host else { return nil }

        guard let rawPath = components.queryItems?
            .first(where: { $0.name == "path" })?.value,
              rawPath.hasPrefix("/") else { return nil }

        let fileURL = URL(fileURLWithPath: rawPath).standardizedFileURL

        switch action {
        case "open":
            return isDirectory(fileURL) ? .open(fileURL) : nil
        case "terminal":
            // URL Scheme 是外部不可信 deep-link，开 shell 前须用户确认（PRD 1214）
            return isDirectory(fileURL) ? .terminal(fileURL, requireConfirmation: true) : nil
        case "reveal":
            return exists(fileURL) ? .reveal([fileURL]) : nil
        default:
            return nil
        }
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(
            atPath: url.path(percentEncoded: false), isDirectory: &isDir
        ) && isDir.boolValue
    }

    private static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }
}
