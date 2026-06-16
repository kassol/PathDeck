import Foundation
import GRDB

final class ChangeStore {
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
            try db.create(table: "change_events") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("path", .text).notNull()
                t.column("fileName", .text).notNull()
                t.column("eventType", .text).notNull()
                t.column("timestamp", .datetime).notNull()
                t.column("directory", .text).notNull().indexed()
            }
        }
        migrator.registerMigration("v2") { db in
            try db.execute(sql: "ALTER TABLE change_events ADD COLUMN terminalSessionID TEXT")
        }
        try migrator.migrate(dbQueue)
    }

    convenience init() throws {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("in.riverflows.PathDeck", isDirectory: true)
        try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        try self.init(databasePath: appSupport.appendingPathComponent("changes.db").path(percentEncoded: false))
    }

    func recordBatch(
        _ events: [(path: String, type: ChangeEventType, directory: String, terminalSessionID: UUID?)]
    ) throws {
        guard !events.isEmpty else { return }
        let now = Date()
        try dbQueue.write { db in
            for event in events {
                let fileName = (event.path as NSString).lastPathComponent
                let sessionStr = event.terminalSessionID?.uuidString
                try db.execute(
                    sql: """
                        INSERT INTO change_events (path, fileName, eventType, timestamp, directory, terminalSessionID)
                        VALUES (?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [event.path, fileName, event.type.rawValue, now, event.directory, sessionStr]
                )
            }
        }
    }

    func recentEvents(in directory: String, limit: Int = 50) throws -> [ChangeEvent] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM change_events
                    WHERE directory = ?
                    ORDER BY timestamp DESC, id DESC
                    LIMIT ?
                    """,
                arguments: [directory, limit]
            )
            return rows.compactMap { row in
                guard let id: Int64 = row["id"],
                      let path: String = row["path"],
                      let fileName: String = row["fileName"],
                      let typeStr: String = row["eventType"],
                      let type = ChangeEventType(rawValue: typeStr),
                      let timestamp: Date = row["timestamp"],
                      let directory: String = row["directory"]
                else { return nil }
                let sessionStr: String? = row["terminalSessionID"]
                let sessionID = sessionStr.flatMap { UUID(uuidString: $0) }
                return ChangeEvent(
                    id: id, path: path, fileName: fileName,
                    eventType: type, timestamp: timestamp, directory: directory,
                    terminalSessionID: sessionID
                )
            }
        }
    }
}
