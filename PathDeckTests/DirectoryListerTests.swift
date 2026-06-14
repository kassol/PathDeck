//
//  DirectoryListerTests.swift
//  PathDeckTests
//
//  Created by kassol on 2026/6/13.
//

import Testing
import Foundation
@testable import PathDeck

struct DirectoryListerTests {

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func listsFilesAndDirectoriesWithMetadata() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        try Data("hello".utf8).write(to: dir.appendingPathComponent("a.txt"))   // 5 bytes
        try Data(count: 12).write(to: dir.appendingPathComponent("b.txt"))
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("sub", isDirectory: true),
            withIntermediateDirectories: true
        )

        let items = try DirectoryLister.list(dir)

        #expect(items.count == 3)

        let sub = try #require(items.first { $0.name == "sub" })
        #expect(sub.isDirectory == true)
        #expect(sub.size == nil)

        let a = try #require(items.first { $0.name == "a.txt" })
        #expect(a.isDirectory == false)
        #expect(a.size == 5)
    }

    @Test func skipsHiddenFilesByDefault() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        try Data().write(to: dir.appendingPathComponent(".hidden"))
        try Data().write(to: dir.appendingPathComponent("visible.txt"))

        let visible = try DirectoryLister.list(dir)
        #expect(visible.count == 1)
        #expect(visible.first?.name == "visible.txt")

        let all = try DirectoryLister.list(dir, includeHidden: true)
        #expect(all.count == 2)
    }
}
