import Foundation

/// 某终端 session 在某时刻的活跃快照，供文件变化归因（S20）。
///
/// 不可变值类型，`Sendable` 以便 `FSWatcher` 后台队列搬运。
struct TerminalActivitySnapshot: Sendable {
    let id: UUID
    /// 该 session 当前工作目录；未知（终端未上报 cwd）时为 nil → 不归因。
    let cwd: URL?
    /// 最近一次成为活跃 tab 的时刻。
    let lastActive: Date
}

/// 文件变化 → 终端 session 的弱关联归因（PRD §R2：活跃期间弱关联，不做虚假精确归因）。
enum TerminalAttribution {
    /// 把 `eventPath` 弱关联到 cwd 落在其祖先链上的终端 session。
    ///
    /// 多命中优先最深 cwd 前缀（最可能的写入者），同深度再取最近活跃；
    /// cwd 缺失或不匹配一律返回 nil（绝不乱归因）。
    static func attribute(eventPath: String, snapshots: [TerminalActivitySnapshot]) -> UUID? {
        let ep = URL(fileURLWithPath: eventPath).standardizedFileURL.path(percentEncoded: false)
        let matches = snapshots.compactMap { snap -> (snapshot: TerminalActivitySnapshot, depth: Int)? in
            guard let cwd = snap.cwd else { return nil }
            let cp = cwd.standardizedFileURL.path(percentEncoded: false)
            let boundary = cp.hasSuffix("/") ? cp : cp + "/"
            guard ep == cp || ep.hasPrefix(boundary) else { return nil }
            return (snap, cp.count)
        }
        return matches.max { lhs, rhs in
            lhs.depth != rhs.depth
                ? lhs.depth < rhs.depth
                : lhs.snapshot.lastActive < rhs.snapshot.lastActive
        }?.snapshot.id
    }
}
