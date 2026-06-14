import Foundation

enum ChangeEventType: String, Sendable {
    case added
    case modified
    case deleted
}

struct ChangeEvent: Identifiable, Hashable, Sendable {
    let id: Int64
    let path: String
    let fileName: String
    let eventType: ChangeEventType
    let timestamp: Date
    let directory: String
}
