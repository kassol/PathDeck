import Foundation

extension Array {
    /// Move a single element from `source` to `destination`, matching SwiftUI
    /// `move(fromOffsets:toOffset:)` single-element semantics: `destination` is
    /// the slot *before which* the element is inserted in the original index
    /// space. `destination == source` and `destination == source + 1` are no-ops.
    mutating func moveElement(from source: Int, to destination: Int) {
        guard indices.contains(source) else { return }
        let clamped = Swift.max(0, Swift.min(destination, count))
        if clamped == source || clamped == source + 1 { return }
        let element = remove(at: source)
        let adjusted = clamped > source ? clamped - 1 : clamped
        insert(element, at: adjusted)
    }
}
