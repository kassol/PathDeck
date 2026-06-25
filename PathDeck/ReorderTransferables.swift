import Foundation
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let pathDeckTerminalSession = UTType(exportedAs: "in.riverflows.PathDeck.terminalSession", conformingTo: .data)
}

struct TerminalSessionDragID: Codable, Transferable {
    let id: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .pathDeckTerminalSession)
    }
}

enum TabDropEdge {
    case start
    case end
}
