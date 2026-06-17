import Foundation

struct FileTab: Identifiable {
    let id: UUID
    var title: String
    var isCustomTitle: Bool
    var mode: WorkspaceMode = .finderFirst
    var isTerminalVisible: Bool = false
    var terminalAnchorCwd: URL?
    var terminalSessionIDs: [UUID]
    var activeTerminalID: UUID?

    init(id: UUID = UUID(), title: String,
         isCustomTitle: Bool = false,
         mode: WorkspaceMode = .finderFirst,
         isTerminalVisible: Bool = false,
         terminalAnchorCwd: URL? = nil,
         terminalSessionIDs: [UUID] = [],
         activeTerminalID: UUID? = nil) {
        self.id = id
        self.title = title
        self.isCustomTitle = isCustomTitle
        self.mode = mode
        self.isTerminalVisible = isTerminalVisible
        self.terminalAnchorCwd = terminalAnchorCwd
        self.terminalSessionIDs = terminalSessionIDs
        self.activeTerminalID = activeTerminalID
    }
}

struct FileTabState: Codable {
    let id: String
    let title: String
    let isCustomTitle: Bool
    let mode: String
    let isTerminalVisible: Bool
    let currentURLPath: String
    let anchorCwdPath: String?
    let terminalStates: [TerminalTabState]
    let activeTerminalIndex: Int?
}
