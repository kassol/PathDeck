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

final class VersionStore: @unchecked Sendable {
    static let defaultMaxVersionsPerFile = 10
    static let defaultMaxFileSizeKB = 1024

    static var maxVersionsPerFile: Int {
        let val = UserDefaults.standard.integer(forKey: "versionMaxCount")
        return val > 0 ? val : defaultMaxVersionsPerFile
    }

    static var maxFileSize: Int {
        let val = UserDefaults.standard.integer(forKey: "versionMaxSizeKB")
        return (val > 0 ? val : defaultMaxFileSizeKB) * 1024
    }

    static var isEnabled: Bool {
        let key = "versionsEnabled"
        return UserDefaults.standard.object(forKey: key) == nil ? true : UserDefaults.standard.bool(forKey: key)
    }

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

    func versionContent(id: Int64) throws -> Data? {
        try dbQueue.read { db in
            try Data.fetchOne(
                db,
                sql: "SELECT content FROM file_versions WHERE id = ?",
                arguments: [id]
            )
        }
    }

    func latestVersionWithContent(for path: String) throws -> (FileVersion, Data)? {
        try dbQueue.read { db in
            let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT id, path, directory, content, contentHash, size, createdAt
                    FROM file_versions WHERE path = ?
                    ORDER BY createdAt DESC, id DESC LIMIT 1
                    """,
                arguments: [path]
            )
            guard let row,
                  let version = Self.fileVersion(from: row),
                  let content: Data = row["content"]
            else { return nil }
            return (version, content)
        }
    }

    func previousVersionWithContent(for path: String, excludingHash hash: String) throws -> (FileVersion, Data)? {
        try dbQueue.read { db in
            let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT id, path, directory, content, contentHash, size, createdAt
                    FROM file_versions WHERE path = ? AND contentHash != ?
                    ORDER BY createdAt DESC, id DESC LIMIT 1
                    """,
                arguments: [path, hash]
            )
            guard let row,
                  let version = Self.fileVersion(from: row),
                  let content: Data = row["content"]
            else { return nil }
            return (version, content)
        }
    }

    static func isEligible(url: URL) -> Bool {
        guard isEnabled else { return false }
        guard let values = try? url.resourceValues(forKeys: [.contentTypeKey, .fileSizeKey]),
              let contentType = values.contentType,
              let fileSize = values.fileSize else { return false }
        return contentType.conforms(to: .text) && fileSize <= maxFileSize
    }

    /// 进目录时对从未快照过的 eligible 文本文件预录基线，建立真正的「修改前」。
    /// 累计内容字节 ≤ byteBudget；超预算停止并置 truncated。可在后台线程跑。
    static func recordBaselines(
        _ store: VersionStore,
        urls: [URL],
        directory: String,
        byteBudget: Int
    ) -> (recorded: Int, skipped: Int, truncated: Bool) {
        var used = 0, recorded = 0, skipped = 0
        var truncated = false
        for url in urls {
            guard Self.isEligible(url: url) else { skipped += 1; continue }
            let path = url.path(percentEncoded: false)
            // 只录从未快照过的文件——避免用「进目录时的当前态」覆盖更早的真基线。
            let alreadyHasVersion = ((try? store.latestVersion(for: path)) ?? nil) != nil
            if alreadyHasVersion { skipped += 1; continue }
            guard let content = try? Data(contentsOf: url) else { skipped += 1; continue }
            if used + content.count > byteBudget { truncated = true; break }
            used += content.count
            try? store.saveVersion(path: path, directory: directory, content: content, hash: content.sha256Hex)
            recorded += 1
        }
        return (recorded, skipped, truncated)
    }

    /// 选择 diff 的「修改前」基线版本（纯函数，可单测）。
    /// latest 存在且 hash≠当前（磁盘=外部脏，未被快照）→ 用 latest 当 before，标记外部脏；
    /// 否则（磁盘=最新快照）→ 用 previous（跳过当前 hash 的上一版）。
    static func selectBaseline(
        latest: (FileVersion, Data)?,
        previous: (FileVersion, Data)?,
        currentHash: String
    ) -> (baseline: (FileVersion, Data)?, isExternallyDirty: Bool) {
        if let latest, latest.0.contentHash != currentHash {
            return (latest, true)
        }
        return (previous, false)
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

/// 把文件恢复到某历史快照内容的纯文件操作（脱离 SwiftUI，端到端可测）。
enum FileRestore {
    /// 先把当前磁盘内容存为新快照（保证可撤销），再原子替换为 snapshotContent。
    static func restore(store: VersionStore, path: String, snapshotContent: Data) throws {
        let url = URL(fileURLWithPath: path)
        let currentData = try Data(contentsOf: url)
        try store.saveVersion(
            path: path,
            directory: (path as NSString).deletingLastPathComponent,
            content: currentData,
            hash: currentData.sha256Hex
        )
        // 写到系统临时替换目录（同卷、唯一），避免在用户目录用固定文件名覆盖既有文件。
        let tempDir = try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: url,
            create: true
        )
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let tempURL = tempDir.appendingPathComponent(url.lastPathComponent)
        try snapshotContent.write(to: tempURL, options: .atomic)
        _ = try FileManager.default.replaceItemAt(url, withItemAt: tempURL)
    }
}
