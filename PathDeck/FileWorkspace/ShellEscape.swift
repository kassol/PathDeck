import Foundation

enum ShellEscape {
    private static let safePattern = try! NSRegularExpression(pattern: "^[A-Za-z0-9_./:@=-]+$")

    static func escape(_ path: String) -> String {
        if path.isEmpty { return "''" }
        let range = NSRange(path.startIndex..., in: path)
        if safePattern.firstMatch(in: path, range: range) != nil {
            return path
        }
        let escaped = path.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }

    static func escapeMultiple(_ paths: [String]) -> String {
        paths.map { escape($0) }.joined(separator: " ")
    }
}
