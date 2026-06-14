import Testing
import Foundation
@testable import PathDeck

@MainActor
struct WorkspaceModelTests {

    @Test func goUpReachesRootAndStops() {
        let model = WorkspaceModel(root: URL(fileURLWithPath: "/Users"))

        model.goUp()
        #expect(model.currentURL.path(percentEncoded: false) == "/")

        model.goUp()
        #expect(model.currentURL.path(percentEncoded: false) == "/")
    }

    // MARK: - Sort

    private static let testItems: [FileItem] = [
        FileItem(url: URL(fileURLWithPath: "/tmp/b.txt"), name: "b.txt", isDirectory: false,
                 size: 200, modifiedDate: Date(timeIntervalSince1970: 2000), kind: "Text"),
        FileItem(url: URL(fileURLWithPath: "/tmp/a.txt"), name: "a.txt", isDirectory: false,
                 size: 100, modifiedDate: Date(timeIntervalSince1970: 3000), kind: "Text"),
        FileItem(url: URL(fileURLWithPath: "/tmp/sub"), name: "sub", isDirectory: true,
                 size: nil, modifiedDate: Date(timeIntervalSince1970: 1000), kind: "Folder"),
        FileItem(url: URL(fileURLWithPath: "/tmp/z.png"), name: "z.png", isDirectory: false,
                 size: nil, modifiedDate: nil, kind: "Image"),
        FileItem(url: URL(fileURLWithPath: "/tmp/dir2"), name: "dir2", isDirectory: true,
                 size: nil, modifiedDate: Date(timeIntervalSince1970: 4000), kind: "Folder"),
    ]

    @Test func sortByNameAscending() {
        let sorted = WorkspaceModel.sortedItems(Self.testItems, by: .name, ascending: true)
        let names = sorted.map(\.name)
        #expect(names == ["dir2", "sub", "a.txt", "b.txt", "z.png"])
    }

    @Test func sortByNameDescending() {
        let sorted = WorkspaceModel.sortedItems(Self.testItems, by: .name, ascending: false)
        let names = sorted.map(\.name)
        #expect(names == ["sub", "dir2", "z.png", "b.txt", "a.txt"])
    }

    @Test func sortBySizeNilsAtEnd() {
        let sorted = WorkspaceModel.sortedItems(Self.testItems, by: .size, ascending: true)
        let names = sorted.map(\.name)
        // dirs first (both nil size, stable-ish), then files: 100, 200, nil
        #expect(sorted.first!.isDirectory)
        let files = sorted.filter { !$0.isDirectory }
        #expect(files.map(\.name) == ["a.txt", "b.txt", "z.png"])
    }

    @Test func sortByDateDescendingNilsAtEnd() {
        let sorted = WorkspaceModel.sortedItems(Self.testItems, by: .date, ascending: false)
        let files = sorted.filter { !$0.isDirectory }
        #expect(files.last?.name == "z.png") // nil date at end
        #expect(files.first?.name == "a.txt") // most recent date
    }

    @Test func directoriesAlwaysBeforeFiles() {
        for col in [SortColumn.name, .date, .size, .kind] {
            for asc in [true, false] {
                let sorted = WorkspaceModel.sortedItems(Self.testItems, by: col, ascending: asc)
                let types = sorted.map(\.isDirectory)
                let firstFileIndex = types.firstIndex(of: false) ?? types.count
                let lastDirIndex = types.lastIndex(of: true) ?? -1
                #expect(lastDirIndex < firstFileIndex,
                        "dirs must precede files for \(col) \(asc ? "asc" : "desc")")
            }
        }
    }
}
