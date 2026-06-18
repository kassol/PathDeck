import Foundation
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let pathDeckFileTab = UTType(exportedAs: "in.riverflows.PathDeck.fileTab", conformingTo: .data)
    static let pathDeckTerminalSession = UTType(exportedAs: "in.riverflows.PathDeck.terminalSession", conformingTo: .data)
}

struct FileTabDragID: Codable, Transferable {
    let id: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .pathDeckFileTab)
    }
}

struct TerminalSessionDragID: Codable, Transferable {
    let id: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .pathDeckTerminalSession)
    }
}

enum TabDropEdge {
    case start  // leading (horizontal) / top (vertical)
    case end    // trailing (horizontal) / bottom (vertical)
}
