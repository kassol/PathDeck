import Foundation
import GRDB
import CryptoKit
import UniformTypeIdentifiers

struct FileVersion: Identifiable, Sendable {
    let id: Int64
    let path: String
    let directory: String
    let contentHash: String
    let size: Int
    let createdAt: Date
}

final class VersionStore {
    static let maxVersionsPerFile = 10
    static let maxFileSize = 1_048_576 // 1MB

    private let dbQueue: DatabaseQueue

    init(databasePath: String) throws {
        var config = Configuration()
        config.busyMode = .timeout(5)
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA journal_mode = WAL")
            try db.execute(sql: "PRAGMA synchronous = NORMAL")
        }

        dbQueue = try DatabaseQueue(path: databasePath, configuration: config)

        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.execute(sql: "PRAGMA auto_vacuum = INCREMENTAL")
            try db.create(table: "file_versions") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("path", .text).notNull()
                t.column("directory", .text).notNull()
                t.column("content", .blob).notNull()
                t.column("contentHash", .text).notNull()
                t.column("size", .integer).notNull()
                t.column("createdAt", .datetime).notNull()
            }
            try db.execute(sql: "CREATE INDEX idx_versions_path ON file_versions(path, createdAt DESC, id DESC)")
            try db.execute(sql: "CREATE INDEX idx_versions_directory ON file_versions(directory)")
        }
        try migrator.migrate(dbQueue)
    }

    convenience init() throws {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("in.riverflows.PathDeck", isDirectory: true)
        try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        try self.init(databasePath: appSupport.appendingPathComponent("versions.db").path(percentEncoded: false))
    }

    func saveVersion(path: String, directory: String, content: Data, hash: String) throws {
        try dbQueue.write { db in
            let latestHash = try String.fetchOne(
                db,
                sql: "SELECT contentHash FROM file_versions WHERE path = ? ORDER BY createdAt DESC, id DESC LIMIT 1",
                arguments: [path]
            )
            if latestHash == hash { return }

            try db.execute(
                sql: """
                    INSERT INTO file_versions (path, directory, content, contentHash, size, createdAt)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                arguments: [path, directory, content, hash, content.count, Date()]
            )

            let count = try Int.fetchOne(
                db,
                sql: "SELECT count(*) FROM file_versions WHERE path = ?",
                arguments: [path]
            ) ?? 0

            if count > Self.maxVersionsPerFile {
                try db.execute(
                    sql: """
                        DELETE FROM file_versions WHERE id IN (
                            SELECT id FROM file_versions WHERE path = ?
                            ORDER BY createdAt ASC, id ASC LIMIT ?
                        )
                        """,
                    arguments: [path, count - Self.maxVersionsPerFile]
                )
            }
        }
    }

    func latestVersion(for path: String) throws -> FileVersion? {
        try dbQueue.read { db in
            let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT id, path, directory, contentHash, size, createdAt
                    FROM file_versions WHERE path = ?
                    ORDER BY createdAt DESC, id DESC LIMIT 1
                    """,
                arguments: [path]
            )
            return row.flatMap { Self.fileVersion(from: $0) }
        }
    }

    func versions(for path: String, limit: Int = 10) throws -> [FileVersion] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT id, path, directory, contentHash, size, createdAt
                    FROM file_versions WHERE path = ?
                    ORDER BY createdAt DESC, id DESC LIMIT ?
                    """,
                arguments: [path, limit]
            )
            return rows.compactMap { Self.fileVersion(from: $0) }
        }
    }

    func pathsWithVersions(in directory: String) throws -> [String] {
        try dbQueue.read { db in
            try String.fetchAll(
                db,
                sql: "SELECT DISTINCT path FROM file_versions WHERE directory = ?",
                arguments: [directory]
            )
        }
    }

    static func isEligible(url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.contentTypeKey, .fileSizeKey]),
              let contentType = values.contentType,
              let fileSize = values.fileSize else { return false }
        return contentType.conforms(to: .text) && fileSize <= maxFileSize
    }

    private static func fileVersion(from row: Row) -> FileVersion? {
        guard let id: Int64 = row["id"],
              let path: String = row["path"],
              let directory: String = row["directory"],
              let contentHash: String = row["contentHash"],
              let size: Int = row["size"],
              let createdAt: Date = row["createdAt"]
        else { return nil }
        return FileVersion(
            id: id, path: path, directory: directory,
            contentHash: contentHash, size: size, createdAt: createdAt
        )
    }
}

extension Data {
    var sha256Hex: String {
        SHA256.hash(data: self).map { String(format: "%02x", $0) }.joined()
    }
}
