import Foundation

struct TerminalSession: Identifiable {
    let id: UUID
    var title: String
    let cwd: URL
}
