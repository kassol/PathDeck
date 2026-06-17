import Foundation

struct TerminalSession: Identifiable {
    let id: UUID
    var title: String
    let cwd: URL
    var currentCwd: URL
    var isManuallyRenamed: Bool = false
    /// 最近一次成为活跃 tab 的时刻，供变化归因的同 cwd tie-break（S20）。重启后为 nil。
    var lastActiveAt: Date?

    init(id: UUID, title: String, cwd: URL, isManuallyRenamed: Bool = false) {
        self.id = id
        self.title = title
        self.cwd = cwd
        self.currentCwd = cwd
        self.isManuallyRenamed = isManuallyRenamed
        self.lastActiveAt = nil
    }
}

struct TerminalTabState: Codable {
    let title: String
    let cwdPath: String
    let isManuallyRenamed: Bool

    init(title: String, cwdPath: String, isManuallyRenamed: Bool = false) {
        self.title = title
        self.cwdPath = cwdPath
        self.isManuallyRenamed = isManuallyRenamed
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        cwdPath = try container.decode(String.self, forKey: .cwdPath)
        isManuallyRenamed = try container.decodeIfPresent(Bool.self, forKey: .isManuallyRenamed) ?? false
    }
}
