import Testing
import Foundation
@testable import PathDeck

struct SearchFilterTests {

    private static let testItems: [FileItem] = [
        FileItem(url: URL(fileURLWithPath: "/tmp/README.md"), name: "README.md", isDirectory: false,
                 size: 100, modifiedDate: nil, kind: "Markdown"),
        FileItem(url: URL(fileURLWithPath: "/tmp/readme.txt"), name: "readme.txt", isDirectory: false,
                 size: 50, modifiedDate: nil, kind: "Text"),
        FileItem(url: URL(fileURLWithPath: "/tmp/photo.png"), name: "photo.png", isDirectory: false,
                 size: 200, modifiedDate: nil, kind: "Image"),
        FileItem(url: URL(fileURLWithPath: "/tmp/Documents"), name: "Documents", isDirectory: true,
                 size: nil, modifiedDate: nil, kind: "Folder"),
        FileItem(url: URL(fileURLWithPath: "/tmp/设计稿"), name: "设计稿", isDirectory: true,
                 size: nil, modifiedDate: nil, kind: "Folder"),
        FileItem(url: URL(fileURLWithPath: "/tmp/设计文档.pdf"), name: "设计文档.pdf", isDirectory: false,
                 size: 300, modifiedDate: nil, kind: "PDF"),
    ]

    @Test func emptyQueryReturnsAll() {
        let result = WorkspaceModel.filterItems(Self.testItems, query: "")
        #expect(result.count == Self.testItems.count)
    }

    @Test func exactNameMatch() {
        let result = WorkspaceModel.filterItems(Self.testItems, query: "photo.png")
        #expect(result.count == 1)
        #expect(result.first?.name == "photo.png")
    }

    @Test func substringMatch() {
        let result = WorkspaceModel.filterItems(Self.testItems, query: "read")
        #expect(result.count == 2)
        let names = Set(result.map(\.name))
        #expect(names.contains("README.md"))
        #expect(names.contains("readme.txt"))
    }

    @Test func caseInsensitive() {
        let result = WorkspaceModel.filterItems(Self.testItems, query: "README")
        #expect(result.count == 2)
    }

    @Test func chineseFilenameMatch() {
        let result = WorkspaceModel.filterItems(Self.testItems, query: "设计")
        #expect(result.count == 2)
        let names = Set(result.map(\.name))
        #expect(names.contains("设计稿"))
        #expect(names.contains("设计文档.pdf"))
    }

    @Test func directoryMatchable() {
        let result = WorkspaceModel.filterItems(Self.testItems, query: "Documents")
        #expect(result.count == 1)
        #expect(result.first?.isDirectory == true)
    }
}
