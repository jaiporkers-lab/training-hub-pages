import Foundation
import CSQLite

public struct BackupManifest: Codable, Sendable {
    public let format: Int
    public let created: Date
    public let databaseHash: String
    public let originals: [String]
    public let activityCount: Int
    public let sampleCount: Int
    public let preferencesHash: String?
}

public struct RestoreResult: Sendable {
    public let recoveryBackup: URL
    public let preferences: Data?
}

extension ActivityStore {
    public func createBackup(preferences: Data? = nil) throws -> URL {
        let folder = root.appendingPathComponent("Backups", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let staging = folder.appendingPathComponent(".building-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: staging.appendingPathComponent("Originals"), withIntermediateDirectories: true,
                                              attributes: [.posixPermissions: 0o700])
        do {
            let database = staging.appendingPathComponent("training.sqlite")
            var destination: OpaquePointer?
            guard sqlite3_open(database.path, &destination) == SQLITE_OK, let destination else {
                if let destination { sqlite3_close(destination) }
                throw HubError.message("Could not create the backup database.")
            }
            do {
                try Self.copyDatabase(from: db, to: destination)
                // Publish a self-contained snapshot: readonly restores must not need WAL/SHM sidecars.
                try Self.execute(destination, "PRAGMA journal_mode = DELETE")
            }
            catch { sqlite3_close(destination); throw error }
            sqlite3_close(destination)
            try Self.makePrivate(database)
            let hashes = try Self.originalHashes(db)
            for hash in hashes {
                let source = root.appendingPathComponent("Originals/\(hash).fit")
                try Self.requireRegularFile(source)
                guard try Self.fileHash(source) == hash else { throw HubError.message("An original FIT file is missing or damaged; backup stopped before publishing.") }
                let target = staging.appendingPathComponent("Originals/\(hash).fit")
                try FileManager.default.copyItem(at: source, to: target)
                try Self.makePrivate(target)
            }
            if let preferences { try preferences.write(to: staging.appendingPathComponent("preferences.json"), options: .atomic) }
            let manifest = BackupManifest(format: 1, created: Date(), databaseHash: try Self.fileHash(database), originals: hashes,
                activityCount: try Self.scalar(db, "SELECT COUNT(*) FROM activities"), sampleCount: try Self.scalar(db, "SELECT COUNT(*) FROM samples"),
                preferencesHash: preferences.map(FITImporter.hash))
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(manifest).write(to: staging.appendingPathComponent("manifest.json"), options: .atomic)
            try Self.makePrivate(staging.appendingPathComponent("manifest.json"))
            if preferences != nil { try Self.makePrivate(staging.appendingPathComponent("preferences.json")) }
            _ = try Self.inspectBackup(staging)
            let formatter = DateFormatter(); formatter.dateFormat = "yyyyMMdd-HHmmss"; formatter.locale = Locale(identifier: "en_US_POSIX")
            let target = folder.appendingPathComponent("TrainingHub-\(formatter.string(from: Date()))-\(UUID().uuidString.prefix(8)).thbackup")
            try FileManager.default.moveItem(at: staging, to: target)
            return target
        } catch { try? FileManager.default.removeItem(at: staging); throw error }
    }

    public nonisolated static func inspectBackup(_ folder: URL) throws -> BackupManifest {
        try inspectBackup(folder, database: folder.appendingPathComponent("training.sqlite")).manifest
    }

    private nonisolated static func inspectBackup(_ folder: URL, database: URL) throws -> (manifest: BackupManifest, preferences: Data?) {
        try requireDirectory(folder)
        try requireDirectory(folder.appendingPathComponent("Originals"))
        let manifestURL = folder.appendingPathComponent("manifest.json")
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(BackupManifest.self, from: FITImporter.readFile(manifestURL, limit: 10_000_000))
        guard manifest.format == 1, Set(manifest.originals).count == manifest.originals.count,
              manifest.originals.allSatisfy(validHash) else { throw HubError.message("This backup format or its original-file list is invalid.") }
        try requireRegularFile(database)
        guard try fileHash(database) == manifest.databaseHash else { throw HubError.message("The backup database checksum does not match.") }
        for hash in manifest.originals {
            let file = folder.appendingPathComponent("Originals/\(hash).fit")
            _ = try verifiedOriginal(file, hash: hash)
        }
        var preferences: Data?
        if let hash = manifest.preferencesHash {
            let data = try FITImporter.readFile(folder.appendingPathComponent("preferences.json"), limit: 10_000_000)
            guard FITImporter.hash(data) == hash else { throw HubError.message("The backup preferences checksum does not match.") }
            guard let values = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  values.values.allSatisfy({ $0 is String || $0 is NSNumber }) else { throw HubError.message("The backup preferences format is unsupported.") }
            preferences = data
        }
        let source = try openReadOnly(database)
        defer { sqlite3_close(source) }
        try execute(source, "PRAGMA trusted_schema = OFF")
        let version = try scalar(source, "PRAGMA user_version")
        guard (1...2).contains(version) else {
            throw HubError.message("This backup requires a different app version.")
        }
        try validateSchema(source, version: version)
        let integrity = try statement(source, "PRAGMA quick_check")
        defer { sqlite3_finalize(integrity) }
        guard sqlite3_step(integrity) == SQLITE_ROW, let text = sqlite3_column_text(integrity, 0), String(cString: text) == "ok" else {
            throw HubError.message("The backup database did not pass its integrity check.")
        }
        let foreignKeys = try statement(source, "PRAGMA foreign_key_check")
        defer { sqlite3_finalize(foreignKeys) }
        guard sqlite3_step(foreignKeys) == SQLITE_DONE, try originalHashes(source) == manifest.originals.sorted(),
              try scalar(source, "SELECT COUNT(*) FROM activities") == manifest.activityCount,
              try scalar(source, "SELECT COUNT(*) FROM samples") == manifest.sampleCount else {
            throw HubError.message("The backup database and manifest do not agree.")
        }
        return (manifest, preferences)
    }

    public func restoreBackup(_ folder: URL, currentPreferences: Data? = nil) throws -> RestoreResult {
        // Validate and restore the same private snapshot. Only the declared database file is copied.
        try Self.requireDirectory(folder)
        let database = folder.appendingPathComponent("training.sqlite")
        try Self.requireRegularFile(database)
        let staging = root.appendingPathComponent(".restoring-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: staging) }
        let stagedDatabase = staging.appendingPathComponent("training.sqlite")
        try FileManager.default.copyItem(at: database, to: stagedDatabase)
        let (manifest, preferences) = try Self.inspectBackup(folder, database: stagedDatabase)
        let recovery = try createBackup(preferences: currentPreferences)
        // Originals are immutable and addressed by hash. Keep old originals for recovery.
        for hash in manifest.originals {
            let target = root.appendingPathComponent("Originals/\(hash).fit")
            let source = folder.appendingPathComponent("Originals/\(hash).fit")
            if !FileManager.default.fileExists(atPath: target.path) || (try? Self.fileHash(target)) != hash {
                try Self.verifiedOriginal(source, hash: hash).write(to: target, options: .atomic)
                try Self.makePrivate(target)
            }
        }
        let source = try Self.openReadOnly(stagedDatabase)
        defer { sqlite3_close(source) }
        do {
            try Self.copyDatabase(from: source, to: db)
            try Self.migrate(db)
        } catch {
            try? Self.execute(db, "ROLLBACK")
            let previous = try Self.openReadOnly(recovery.appendingPathComponent("training.sqlite"))
            defer { sqlite3_close(previous) }
            try Self.copyDatabase(from: previous, to: db)
            throw HubError.message("Restore failed. Your previous database was recovered from the automatic backup.")
        }
        return RestoreResult(recoveryBackup: recovery, preferences: preferences)
    }

    private nonisolated static func copyDatabase(from source: OpaquePointer, to target: OpaquePointer) throws {
        guard let backup = sqlite3_backup_init(target, "main", source, "main") else { throw HubError.message("Could not start a consistent database copy.") }
        let status = sqlite3_backup_step(backup, -1)
        let finished = sqlite3_backup_finish(backup)
        guard status == SQLITE_DONE, finished == SQLITE_OK else { throw HubError.message("The database copy could not finish. Please retry when other operations have finished.") }
    }
    private nonisolated static func openReadOnly(_ url: URL) throws -> OpaquePointer {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let header = try handle.read(upToCount: 20) ?? Data()
        guard header.count == 20, header[18] == 1, header[19] == 1 else {
            throw HubError.message("Choose a self-contained Training Hub backup database.")
        }
        var uri = URLComponents(url: url, resolvingAgainstBaseURL: false)
        uri?.queryItems = [URLQueryItem(name: "immutable", value: "1")]
        var pointer: OpaquePointer?
        guard let path = uri?.string,
              sqlite3_open_v2(path, &pointer, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK, let pointer else {
            if let pointer { sqlite3_close(pointer) }
            throw HubError.message("Could not read the backup database.")
        }
        return pointer
    }
    private nonisolated static func validateSchema(_ source: OpaquePointer, version: Int) throws {
        var reference: OpaquePointer?
        defer { if let reference { sqlite3_close(reference) } }
        guard sqlite3_open(":memory:", &reference) == SQLITE_OK, let reference else {
            throw HubError.message("Could not verify the backup schema.")
        }
        try execute(reference, baseSchema)
        if version == 2 { try execute(reference, syncSchema) }
        let query = "SELECT type, name, tbl_name, COALESCE(sql, '') FROM sqlite_master ORDER BY type, name"
        let expected = try statement(reference, query)
        defer { sqlite3_finalize(expected) }
        let actual = try statement(source, query)
        defer { sqlite3_finalize(actual) }
        while true {
            let expectedStatus = sqlite3_step(expected)
            let actualStatus = sqlite3_step(actual)
            if expectedStatus == SQLITE_DONE, actualStatus == SQLITE_DONE { return }
            guard expectedStatus == SQLITE_ROW, actualStatus == SQLITE_ROW,
                  (0..<4).allSatisfy({ column in
                      guard let lhs = sqlite3_column_text(expected, Int32(column)), let rhs = sqlite3_column_text(actual, Int32(column)) else { return false }
                      return String(cString: lhs) == String(cString: rhs)
                  }) else { throw HubError.message("The backup contains an unsupported database schema.") }
        }
    }

    private nonisolated static func verifiedOriginal(_ url: URL, hash: String) throws -> Data {
        let data = try FITImporter.readFile(url)
        guard FITImporter.hash(data) == hash else { throw HubError.message("A backup original checksum does not match.") }
        return data
    }

    private nonisolated static func statement(_ db: OpaquePointer, _ sql: String) throws -> OpaquePointer {
        var pointer: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &pointer, nil) == SQLITE_OK, let pointer else { throw HubError.message("The backup database has an unsupported schema.") }
        return pointer
    }
    private nonisolated static func scalar(_ db: OpaquePointer, _ sql: String) throws -> Int {
        let pointer = try statement(db, sql); defer { sqlite3_finalize(pointer) }
        guard sqlite3_step(pointer) == SQLITE_ROW else { throw HubError.message("The backup database check failed: \(String(cString: sqlite3_errmsg(db))) (\(sql)).") }
        return Int(sqlite3_column_int64(pointer, 0))
    }
    private nonisolated static func originalHashes(_ db: OpaquePointer) throws -> [String] {
        let pointer = try statement(db, "SELECT hash FROM files ORDER BY hash"); defer { sqlite3_finalize(pointer) }
        var result: [String] = []
        while true {
            let status = sqlite3_step(pointer)
            if status == SQLITE_DONE { break }
            guard status == SQLITE_ROW, let text = sqlite3_column_text(pointer, 0) else { throw HubError.message("Could not inspect original files.") }
            let hash = String(cString: text)
            guard validHash(hash) else { throw HubError.message("An original-file identifier is invalid.") }
            result.append(hash)
        }
        return result
    }
    nonisolated static func validHash(_ hash: String) -> Bool { hash.count == 64 && hash.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) } }
    private nonisolated static func fileHash(_ url: URL) throws -> String { FITImporter.hash(try Data(contentsOf: url, options: .mappedIfSafe)) }
    private nonisolated static func requireRegularFile(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw HubError.message("The backup contains a missing or unsafe file.") }
    }
    private nonisolated static func requireDirectory(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw HubError.message("Choose a complete Training Hub backup folder.") }
    }
    private nonisolated static func makePrivate(_ url: URL) throws { try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path) }
}
