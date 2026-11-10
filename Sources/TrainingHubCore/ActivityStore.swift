import Foundation
import CSQLite

// Only the owning actor calls SQLite; the immutable holder also closes safely at final release.
private final class SQLiteConnection: @unchecked Sendable {
    let raw: OpaquePointer
    init(_ raw: OpaquePointer) { self.raw = raw }
    deinit { sqlite3_close(raw) }
}

/// A single actor owns the SQLite connection. Imports and reads never run on the UI thread.
public actor ActivityStore {
    public let root: URL
    private let connection: SQLiteConnection
    var db: OpaquePointer { connection.raw }
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(root: URL) throws {
        self.root = root
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Originals"), withIntermediateDirectories: true,
                                              attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        let url = root.appendingPathComponent("training.sqlite")
        var connection: OpaquePointer?
        guard sqlite3_open_v2(url.path, &connection, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK, let connection else {
            if let connection { sqlite3_close(connection) }
            throw HubError.message("Could not open the local activity database.")
        }
        do {
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            sqlite3_busy_timeout(connection, 5_000)
            try Self.execute(connection, "PRAGMA foreign_keys = ON")
            try Self.execute(connection, "PRAGMA journal_mode = WAL")
            var versionStatement: OpaquePointer?
            sqlite3_prepare_v2(connection, "PRAGMA user_version", -1, &versionStatement, nil)
            defer { sqlite3_finalize(versionStatement) }
            guard sqlite3_step(versionStatement) == SQLITE_ROW, sqlite3_column_int(versionStatement, 0) <= 2 else {
                throw HubError.message("This database needs a newer version of Training Hub.")
            }
            try Self.execute(connection, "PRAGMA trusted_schema = OFF")
            try Self.execute(connection, Self.baseSchema)
            try Self.migrate(connection)
        } catch {
            sqlite3_close(connection)
            throw error
        }
        self.connection = SQLiteConnection(connection)
    }

    public func importFile(_ url: URL, isDemo: Bool = false) throws -> Int {
        let data = try FITImporter.readFile(url)
        let fileHash = FITImporter.hash(data)
        guard try !exists(fileHash) else { return 0 }
        let decoded = try FITImporter.decode(data, name: url.deletingPathExtension().lastPathComponent, isDemo: isDemo)
        let original = root.appendingPathComponent("Originals/\(fileHash).fit")
        // Archive first: a crash may leave an unindexed original, never a database row without its source.
        try data.write(to: original, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: original.path)
        try Self.execute(db, "BEGIN IMMEDIATE")
        do {
            try run("INSERT INTO files VALUES (?, ?, ?)", [.text(fileHash), .text(url.lastPathComponent), .number(isDemo ? 1 : 0)])
            for item in decoded {
                try run("INSERT INTO activities VALUES (?, ?, ?, ?)", [.text(item.activity.id), .text(fileHash),
                    .number(item.activity.start.timeIntervalSince1970), .blob(try encoder.encode(item.activity))])
            }
            // Reuse a prepared statement; large recordings must not prepare once per sample.
            let statement = try prepare("INSERT INTO samples VALUES (?, ?, ?, ?)")
            defer { sqlite3_finalize(statement) }
            for item in decoded {
                for sample in item.samples {
                    sqlite3_reset(statement)
                    sqlite3_clear_bindings(statement)
                    try bind([.text(item.activity.id), .number(Double(sample.id)), .number(sample.elapsed), .blob(try encoder.encode(sample))], to: statement)
                    guard sqlite3_step(statement) == SQLITE_DONE else { throw databaseError() }
                }
            }
            try Self.execute(db, "COMMIT")
            return decoded.count
        } catch {
            try? Self.execute(db, "ROLLBACK")
            throw error
        }
    }

    public func activities() throws -> [Activity] {
        let statement = try prepare("SELECT metadata, activity_titles.title FROM activities LEFT JOIN activity_titles ON activities.file_hash = activity_titles.file_hash ORDER BY start DESC, id")
        defer { sqlite3_finalize(statement) }
        var result: [Activity] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { break }
            guard status == SQLITE_ROW else { throw databaseError() }
            var activity = try decoder.decode(Activity.self, from: blob(statement, column: 0))
            if let text = sqlite3_column_text(statement, 1) {
                let title = String(cString: text)
                let marker = " · \(activity.sessionIndex + 1). "
                let legacy = " · Session \(activity.sessionIndex + 1)"
                if let range = activity.title.range(of: marker, options: .backwards) ?? activity.title.range(of: legacy, options: .backwards) {
                    activity.title = title + activity.title[range.lowerBound...]
                } else { activity.title = title }
            }
            result.append(activity)
        }
        return result
    }

    public func exportCSV(_ text: String, suggestedName: String) throws -> URL {
        let directory = root.appendingPathComponent("Exports", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                              attributes: [.posixPermissions: 0o700])
        var base = suggestedName.hasSuffix(".csv") ? String(suggestedName.dropLast(4)) : suggestedName
        base = base.components(separatedBy: .controlCharacters).joined()
            .replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: "\\", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        while base.utf8.count > 180 { base.removeLast() }
        if base.isEmpty { base = "activity" }
        let url = directory.appendingPathComponent("\(base)-\(UUID().uuidString.prefix(8)).csv")
        try Data(text.utf8).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return url
    }

    public func samples(for id: String) throws -> [Sample] {
        if id.hasPrefix(ActivityGroup.idPrefix) {
            let fileHash = String(id.dropFirst(ActivityGroup.idPrefix.count))
            let statement = try prepare("SELECT metadata FROM activities WHERE file_hash = ? ORDER BY start, id")
            defer { sqlite3_finalize(statement) }
            try bind([.text(fileHash)], to: statement)
            var sessions: [Activity] = []
            while true {
                let status = sqlite3_step(statement)
                if status == SQLITE_DONE { break }
                guard status == SQLITE_ROW else { throw databaseError() }
                sessions.append(try decoder.decode(Activity.self, from: blob(statement, column: 0)))
            }
            guard !sessions.isEmpty else { return [] }
            let group = ActivityGroup(sessions: sessions)
            return try group.combinedSamples(group.sessions.map { try samples(for: $0.id) })
        }
        let statement = try prepare("SELECT data FROM samples WHERE activity_id = ? ORDER BY ordinal")
        defer { sqlite3_finalize(statement) }
        try bind([.text(id)], to: statement)
        var result: [Sample] = []
        while true {
            if result.count.isMultiple(of: 512) { try Task.checkCancellation() }
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { break }
            guard status == SQLITE_ROW else { throw databaseError() }
            result.append(try decoder.decode(Sample.self, from: blob(statement, column: 0)))
        }
        return result
    }

    private func exists(_ hash: String) throws -> Bool {
        let statement = try prepare("SELECT 1 FROM files WHERE hash = ?")
        defer { sqlite3_finalize(statement) }
        try bind([.text(hash)], to: statement)
        let status = sqlite3_step(statement)
        guard status == SQLITE_ROW || status == SQLITE_DONE else { throw databaseError() }
        return status == SQLITE_ROW
    }

    enum Binding { case text(String), number(Double), blob(Data) }
    func run(_ sql: String, _ values: [Binding]) throws {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        try bind(values, to: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw databaseError() }
    }
    func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw databaseError() }
        return statement
    }
    func bind(_ values: [Binding], to statement: OpaquePointer) throws {
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            let status: Int32
            switch value {
            case .text(let text): status = sqlite3_bind_text(statement, index, text, -1, transient)
            case .number(let number): status = sqlite3_bind_double(statement, index, number)
            case .blob(let data): status = data.withUnsafeBytes { sqlite3_bind_blob(statement, index, $0.baseAddress, Int32(data.count), transient) }
            }
            guard status == SQLITE_OK else { throw databaseError() }
        }
    }
    func blob(_ statement: OpaquePointer, column: Int32) -> Data {
        guard let pointer = sqlite3_column_blob(statement, column) else { return Data() }
        return Data(bytes: pointer, count: Int(sqlite3_column_bytes(statement, column)))
    }
    func databaseError() -> HubError { .message("Local database: \(String(cString: sqlite3_errmsg(db)))") }
    static func execute(_ db: OpaquePointer?, _ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw HubError.message("Local database: \(String(cString: sqlite3_errmsg(db)))")
        }
    }

    static let baseSchema = """
        CREATE TABLE IF NOT EXISTS files(hash TEXT PRIMARY KEY, original_name TEXT NOT NULL, demo INTEGER NOT NULL);
        CREATE TABLE IF NOT EXISTS activities(id TEXT PRIMARY KEY, file_hash TEXT NOT NULL REFERENCES files(hash), start REAL NOT NULL, metadata BLOB NOT NULL);
        CREATE TABLE IF NOT EXISTS samples(activity_id TEXT NOT NULL REFERENCES activities(id), ordinal INTEGER NOT NULL, elapsed REAL NOT NULL, data BLOB NOT NULL, PRIMARY KEY(activity_id, ordinal));
        CREATE INDEX IF NOT EXISTS activity_start ON activities(start DESC);
        """

    static let syncSchema = """
        CREATE TABLE IF NOT EXISTS activity_titles(file_hash TEXT PRIMARY KEY REFERENCES files(hash), title TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS garmin_sources(activity_id TEXT PRIMARY KEY, file_hash TEXT NOT NULL REFERENCES files(hash));
        CREATE TABLE IF NOT EXISTS garmin_pending(scope TEXT NOT NULL, activity_id TEXT NOT NULL, name TEXT NOT NULL, error TEXT NOT NULL, PRIMARY KEY(scope, activity_id));
        CREATE TABLE IF NOT EXISTS sync_state(key TEXT PRIMARY KEY, value TEXT NOT NULL);
        """

    static func migrate(_ db: OpaquePointer?) throws {
        try execute(db, "BEGIN IMMEDIATE; " + syncSchema + " PRAGMA user_version = 2; COMMIT;")
    }

    public func renameActivity(fileHash: String, title: String) throws {
        let value = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= 200 else { throw HubError.message("Use an activity name between 1 and 200 characters.") }
        try run("INSERT INTO activity_titles VALUES (?, ?) ON CONFLICT(file_hash) DO UPDATE SET title = excluded.title", [.text(fileHash), .text(value)])
    }

    /// Remove only explicitly synthetic files; a verified snapshot allows recovery.
    public func removeDemoActivities(preferences: Data? = nil) throws -> URL? {
        guard try activities().contains(where: \.isDemo) else { return nil }
        let recovery = try createBackup(preferences: preferences)
        try Self.execute(db, "BEGIN IMMEDIATE")
        do {
            try Self.execute(db, "DELETE FROM samples WHERE activity_id IN (SELECT id FROM activities WHERE file_hash IN (SELECT hash FROM files WHERE demo = 1))")
            try Self.execute(db, "DELETE FROM activity_titles WHERE file_hash IN (SELECT hash FROM files WHERE demo = 1)")
            try Self.execute(db, "DELETE FROM garmin_sources WHERE file_hash IN (SELECT hash FROM files WHERE demo = 1)")
            try Self.execute(db, "DELETE FROM activities WHERE file_hash IN (SELECT hash FROM files WHERE demo = 1)")
            try Self.execute(db, "DELETE FROM files WHERE demo = 1")
            try Self.execute(db, "COMMIT")
        } catch { try? Self.execute(db, "ROLLBACK"); throw error }
        // Immutable originals stay on disk and in the recovery snapshot.
        return recovery
    }
}
