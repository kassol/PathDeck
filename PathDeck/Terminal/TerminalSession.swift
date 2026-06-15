import Foundation

struct TerminalSession: Identifiable {
    let id: UUID
    var title: String
    let cwd: URL
    var currentCwd: URL

    init(id: UUID, title: String, cwd: URL) {
        self.id = id
        self.title = title
        self.cwd = cwd
        self.currentCwd = cwd
    }
}
