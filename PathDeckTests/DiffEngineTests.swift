import Testing
import Foundation
@testable import PathDeck

@Suite
struct DiffEngineTests {
    @Test
    func identicalTexts() {
        let text = "line1\nline2\nline3"
        let result = DiffEngine.diff(old: text, new: text)
        #expect(result.allSatisfy { $0.type == .unchanged })
        #expect(result.count == 3)
    }

    @Test
    func emptyOld() {
        let result = DiffEngine.diff(old: "", new: "a\nb")
        let added = result.filter { $0.type == .added }
        #expect(added.count == 2)
        #expect(added[0].text == "a")
        #expect(added[1].text == "b")
    }

    @Test
    func emptyNew() {
        let result = DiffEngine.diff(old: "a\nb", new: "")
        let deleted = result.filter { $0.type == .deleted }
        #expect(deleted.count == 2)
    }

    @Test
    func bothEmpty() {
        let result = DiffEngine.diff(old: "", new: "")
        #expect(result.isEmpty)
    }

    @Test
    func singleLineChange() {
        let result = DiffEngine.diff(old: "hello", new: "world")
        let deleted = result.filter { $0.type == .deleted }
        let added = result.filter { $0.type == .added }
        #expect(deleted.count == 1)
        #expect(deleted[0].text == "hello")
        #expect(added.count == 1)
        #expect(added[0].text == "world")
    }

    @Test
    func multiLineInsert() {
        let old = "a\nb\nc"
        let new = "a\nb\nX\nY\nc"
        let result = DiffEngine.diff(old: old, new: new)
        let added = result.filter { $0.type == .added }
        #expect(added.count == 2)
        #expect(added[0].text == "X")
        #expect(added[1].text == "Y")
        let unchanged = result.filter { $0.type == .unchanged }
        #expect(unchanged.count == 3)
    }

    @Test
    func multiLineDelete() {
        let old = "a\nb\nc\nd"
        let new = "a\nd"
        let result = DiffEngine.diff(old: old, new: new)
        let deleted = result.filter { $0.type == .deleted }
        #expect(deleted.count == 2)
        #expect(deleted.map(\.text) == ["b", "c"])
    }

    @Test
    func lineNumbersCorrect() {
        let old = "a\nb\nc"
        let new = "a\nX\nc"
        let result = DiffEngine.diff(old: old, new: new)

        let unchanged1 = result.first { $0.type == .unchanged && $0.text == "a" }
        #expect(unchanged1?.oldLineNumber == 1)
        #expect(unchanged1?.newLineNumber == 1)

        let deleted = result.first { $0.type == .deleted }
        #expect(deleted?.oldLineNumber == 2)
        #expect(deleted?.newLineNumber == nil)

        let added = result.first { $0.type == .added }
        #expect(added?.oldLineNumber == nil)
        #expect(added?.newLineNumber == 2)
    }

    @Test
    func mixedChanges() {
        let old = "1\n2\n3\n4\n5"
        let new = "1\n2a\n3\n6\n5"
        let result = DiffEngine.diff(old: old, new: new)
        #expect(!result.isEmpty)
        let unchanged = result.filter { $0.type == .unchanged }
        #expect(unchanged.count >= 2)
    }

    @Test
    func uniqueIds() {
        let result = DiffEngine.diff(old: "a\nb\nc", new: "x\ny\nz")
        let ids = result.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test
    func largeInput() {
        let oldLines = (0..<1000).map { "line \($0)" }.joined(separator: "\n")
        let newLines = (0..<1000).map { $0 == 500 ? "CHANGED" : "line \($0)" }.joined(separator: "\n")
        let result = DiffEngine.diff(old: oldLines, new: newLines)
        let deleted = result.filter { $0.type == .deleted }
        let added = result.filter { $0.type == .added }
        #expect(deleted.count == 1)
        #expect(added.count == 1)
    }
}
