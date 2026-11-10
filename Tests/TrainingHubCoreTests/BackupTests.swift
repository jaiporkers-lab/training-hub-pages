import XCTest
import Foundation
import CSQLite
@testable import TrainingHubCore

final class BackupTests: XCTestCase, @unchecked Sendable {
    func testVerifiedBackupRestoreAndRecoveryPreserveOriginalsNamesAndPreferences() async throws {
        let root = temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try ActivityStore(root: root)
        let first = root.appendingPathComponent("First.fit")
        try DemoFIT.make(multisport: true).write(to: first)
        _ = try await store.importFile(first)
        let hash = FITImporter.hash(try Data(contentsOf: first))
        try await store.renameActivity(fileHash: hash, title: "Race, renamed")
        let preferences = Data("{\"zones.running.heartRate\":\"140,160\"}".utf8)
        let backup = try await store.createBackup(preferences: preferences)
        let manifest = try ActivityStore.inspectBackup(backup)
        XCTAssertEqual(manifest.originals.count, 1)
        XCTAssertEqual(manifest.activityCount, 2)
        XCTAssertEqual(manifest.sampleCount, 721)
        let second = root.appendingPathComponent("Second.fit")
        try DemoFIT.make(variant: 1).write(to: second)
        _ = try await store.importFile(second)
        try await store.renameActivity(fileHash: hash, title: "Changed after backup")
        let result = try await store.restoreBackup(backup)
        XCTAssertEqual(result.preferences, preferences)
        XCTAssertEqual(try ActivityStore.inspectBackup(result.recoveryBackup).activityCount, 3)
        let restored = try await store.activities()
        XCTAssertEqual(restored.count, 2)
        XCTAssertEqual(ActivityGroup.grouping(restored).first?.summary.title, "Race, renamed")
        let samples = try await store.samples(for: restored[0].id)
        XCTAssertGreaterThan(samples.count, 0)
        let reopened = try ActivityStore(root: root)
        let persisted = try await reopened.activities()
        XCTAssertEqual(persisted.count, 2)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Originals/\(hash).fit")), try Data(contentsOf: first))
    }

    func testCorruptBackupIsRejectedBeforeReplacingLiveData() async throws {
        let root = temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try ActivityStore(root: root)
        let file = root.appendingPathComponent("Ride.fit")
        try DemoFIT.make().write(to: file)
        _ = try await store.importFile(file)
        let backup = try await store.createBackup()
        let database = backup.appendingPathComponent("training.sqlite")
        var data = try Data(contentsOf: database); data[data.count / 2] ^= 1; try data.write(to: database)
        do { _ = try await store.restoreBackup(backup); XCTFail("Must reject corruption") } catch {}
        let unchanged = try await store.activities()
        XCTAssertEqual(unchanged.count, 1)
    }

    func testRehashedBackupWithTriggerIsRejectedBeforeRestore() async throws {
        let root = temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try ActivityStore(root: root)
        let backup = try await store.createBackup()
        let database = backup.appendingPathComponent("training.sqlite")
        var connection: OpaquePointer?
        XCTAssertEqual(sqlite3_open(database.path, &connection), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(connection, "CREATE TRIGGER erase AFTER INSERT ON activity_titles BEGIN DELETE FROM samples; END;", nil, nil, nil), SQLITE_OK)
        sqlite3_close(connection)
        try refreshHash(in: backup)
        let file = root.appendingPathComponent("Ride.fit")
        try DemoFIT.make().write(to: file)
        _ = try await store.importFile(file)
        XCTAssertThrowsError(try ActivityStore.inspectBackup(backup))
        do { _ = try await store.restoreBackup(backup); XCTFail("Must reject an altered schema") } catch {}
        let activities = try await store.activities()
        XCTAssertEqual(activities.count, 1)
        try await store.renameActivity(fileHash: activities[0].fileHash, title: "Ride")
        let samples = try await store.samples(for: activities[0].id)
        XCTAssertFalse(samples.isEmpty)
    }

    func testRestoreIgnoresSidecarsAndRejectsWALModeDatabase() async throws {
        let root = temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try ActivityStore(root: root)
        let backup = try await store.createBackup()
        let database = backup.appendingPathComponent("training.sqlite")
        let journal = backup.appendingPathComponent("training.sqlite-journal")
        try Data("untrusted sidecar".utf8).write(to: journal)
        _ = try ActivityStore.inspectBackup(backup)
        _ = try await store.restoreBackup(backup)
        try FileManager.default.removeItem(at: journal)
        var connection: OpaquePointer?
        XCTAssertEqual(sqlite3_open(database.path, &connection), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(connection, "PRAGMA journal_mode=WAL", nil, nil, nil), SQLITE_OK)
        sqlite3_close(connection)
        try refreshHash(in: backup)
        XCTAssertThrowsError(try ActivityStore.inspectBackup(backup))
    }

    func testImportRejectsSpecialAndOversizedFilesBeforeDecoding() async throws {
        let root = temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try ActivityStore(root: root)
        let original = root.appendingPathComponent("Ride.fit")
        try DemoFIT.make().write(to: original)
        let symlink = root.appendingPathComponent("Link.fit")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: original)
        let large = root.appendingPathComponent("Large.fit")
        try Data().write(to: large)
        let handle = try FileHandle(forWritingTo: large)
        try handle.truncate(atOffset: UInt64(FITImporter.maximumFileSize + 1))
        try handle.close()
        let pipe = root.appendingPathComponent("Pipe.fit")
        XCTAssertEqual(mkfifo(pipe.path, 0o600), 0)
        for file in [symlink, large, pipe] {
            do { _ = try await store.importFile(file); XCTFail("Must reject unsafe FIT input") } catch {}
        }
        let activities = try await store.activities()
        XCTAssertTrue(activities.isEmpty)
    }

    func testOriginalCorruptionAndSymlinksAreRejected() async throws {
        let root = temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try ActivityStore(root: root)
        let file = root.appendingPathComponent("Ride.fit")
        try DemoFIT.make().write(to: file)
        _ = try await store.importFile(file)
        let backup = try await store.createBackup()
        let manifest = try ActivityStore.inspectBackup(backup)
        let original = backup.appendingPathComponent("Originals/\(manifest.originals[0]).fit")
        try FileManager.default.removeItem(at: original)
        try FileManager.default.createSymbolicLink(at: original, withDestinationURL: file)
        XCTAssertThrowsError(try ActivityStore.inspectBackup(backup))
        try FileManager.default.removeItem(at: original)
        try Data("corrupt".utf8).write(to: original)
        XCTAssertThrowsError(try ActivityStore.inspectBackup(backup))
    }

    func testManifestPathTraversalAndInconsistentCountsAreRejected() async throws {
        let root = temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try ActivityStore(root: root)
        let backup = try await store.createBackup()
        let url = backup.appendingPathComponent("manifest.json")
        let original = try Data(contentsOf: url)
        var manifest = try JSONSerialization.jsonObject(with: original) as! [String: Any]
        manifest["originals"] = ["../outside"]
        try JSONSerialization.data(withJSONObject: manifest).write(to: url)
        XCTAssertThrowsError(try ActivityStore.inspectBackup(backup))
        manifest = try JSONSerialization.jsonObject(with: original) as! [String: Any]
        manifest["sampleCount"] = 100
        try JSONSerialization.data(withJSONObject: manifest).write(to: url)
        XCTAssertThrowsError(try ActivityStore.inspectBackup(backup))
    }

    func testFirstSyncSafetyBackupIsCreatedOnlyOnce() async throws {
        let root = temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try ActivityStore(root: root)
        let file = root.appendingPathComponent("Ride.fit"); try DemoFIT.make().write(to: file)
        _ = try await store.importFile(file)
        let first = try await store.ensureFirstSyncBackup()
        let second = try await store.ensureFirstSyncBackup()
        XCTAssertNotNil(first); XCTAssertNil(second)
    }

    func testVersionOneBackupRestoresThroughAdditiveMigration() async throws {
        let root = temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try ActivityStore(root: root)
        let file = root.appendingPathComponent("Ride.fit"); try DemoFIT.make().write(to: file)
        _ = try await store.importFile(file)
        let backup = try await store.createBackup()
        let database = backup.appendingPathComponent("training.sqlite")
        var connection: OpaquePointer?
        XCTAssertEqual(sqlite3_open(database.path, &connection), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(connection, "DROP TABLE activity_titles; DROP TABLE garmin_sources; DROP TABLE garmin_pending; DROP TABLE sync_state; PRAGMA user_version=1", nil, nil, nil), SQLITE_OK)
        sqlite3_close(connection)
        try refreshHash(in: backup)
        _ = try ActivityStore.inspectBackup(backup)
        _ = try await store.restoreBackup(backup)
        let activities = try await store.activities()
        XCTAssertEqual(activities.count, 1)
        try await store.renameActivity(fileHash: activities[0].fileHash, title: "Migrated")
        let renamed = try await store.activities()
        XCTAssertEqual(renamed[0].title, "Migrated")
    }

    func testRenameChangesDisplayWithoutChangingOriginalOrIDs() async throws {
        let root = temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try ActivityStore(root: root)
        let file = root.appendingPathComponent("Brick.fit"); let data = try DemoFIT.make(multisport: true); try data.write(to: file)
        _ = try await store.importFile(file)
        let before = try await store.activities()
        try await store.renameActivity(fileHash: FITImporter.hash(data), title: "My race")
        let after = try await store.activities()
        XCTAssertEqual(before.map(\.id), after.map(\.id))
        XCTAssertEqual(ActivityGroup.grouping(after).first?.summary.title, "My race")
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Originals/\(FITImporter.hash(data)).fit")), data)
    }

    private func refreshHash(in backup: URL) throws {
        let manifestURL = backup.appendingPathComponent("manifest.json")
        var manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as! [String: Any]
        manifest["databaseHash"] = FITImporter.hash(try Data(contentsOf: backup.appendingPathComponent("training.sqlite")))
        try JSONSerialization.data(withJSONObject: manifest).write(to: manifestURL)
    }

    private func temporary() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("HubBackupTests-\(UUID().uuidString)") }
}
