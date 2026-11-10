import XCTest
import Foundation
import CSQLite
@testable import TrainingHubCore

final class PipelineTests: XCTestCase, @unchecked Sendable {
    func testOfficialSDKRoundTripAndUnits() throws {
        let data = try DemoFIT.make()
        let decoded = try FITImporter.decode(data, name: "Ride")
        let session = try XCTUnwrap(decoded.first)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(session.activity.sport, "cycling")
        XCTAssertEqual(session.activity.distance, 12_600)
        XCTAssertEqual(session.activity.timer, 1_800)
        XCTAssertEqual(session.samples.count, 361)
        XCTAssertEqual(session.samples.first?.elapsed, 0)
        XCTAssertEqual(session.samples.last?.elapsed, 1_800)
        XCTAssertEqual(session.samples.first?.speed, 7)
        XCTAssertEqual(Metric.speed.value(session.samples[0])!, 25.2, accuracy: 0.001)
        XCTAssertEqual(session.activity.laps.count, 1)
        XCTAssertEqual(session.activity.start.timeIntervalSince1970, 1_793_617_200)
    }

    func testMissingSensorsStayNil() throws {
        let session = try XCTUnwrap(FITImporter.decode(DemoFIT.make(omitSensors: true), name: "No sensors").first)
        XCTAssertNil(session.activity.avgHeartRate)
        XCTAssertNil(session.activity.avgPower)
        XCTAssertTrue(session.samples.allSatisfy { $0.heartRate == nil && $0.power == nil && $0.cadence == nil })
        XCTAssertNotNil(session.samples.first?.speed)
    }

    func testMultisportBoundaryDoesNotDuplicateSamples() throws {
        let decoded = try FITImporter.decode(DemoFIT.make(multisport: true), name: "Brick")
        XCTAssertEqual(decoded.count, 2)
        XCTAssertEqual(decoded.map(\.activity.sport), ["cycling", "running"])
        XCTAssertEqual(decoded.map { $0.samples.count }, [360, 361])
        XCTAssertEqual(decoded[1].samples.first?.elapsed, 0)
        XCTAssertEqual(decoded[1].samples.first?.distance, 0)
        XCTAssertLessThan(decoded[0].samples.last!.timestamp, decoded[1].samples.first!.timestamp)
        XCTAssertNotEqual(decoded[0].activity.id, decoded[1].activity.id)
    }

    func testRejectsCorruptAndTruncatedFIT() throws {
        let data = try DemoFIT.make()
        var corrupt = data
        corrupt[corrupt.count - 1] ^= 0xff
        XCTAssertThrowsError(try FITImporter.decode(corrupt, name: "Corrupt"))
        XCTAssertThrowsError(try FITImporter.decode(Data(data.dropLast(25)), name: "Truncated"))
        XCTAssertThrowsError(try FITImporter.decode(Data("hello".utf8), name: "Other"))
    }

    func testImportArchiveDuplicatesAndReopen() async throws {
        let root = temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let data = try DemoFIT.make()
        let file = root.appendingPathComponent("Ride.fit")
        try data.write(to: file)
        let store = try ActivityStore(root: root.appendingPathComponent("Library"))
        let first = try await store.importFile(file)
        XCTAssertEqual(first, 1)
        let renamed = root.appendingPathComponent("Renamed.fit")
        try data.write(to: renamed)
        let second = try await store.importFile(renamed)
        XCTAssertEqual(second, 0)
        let activities = try await store.activities()
        let activity = try XCTUnwrap(activities.first)
        XCTAssertEqual(activities.count, 1)
        let samples = try await store.samples(for: activity.id)
        XCTAssertEqual(samples.count, activity.sampleCount)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Library/Originals/\(activity.fileHash).fit")), data)
        let reopened = try ActivityStore(root: root.appendingPathComponent("Library"))
        let persisted = try await reopened.samples(for: activity.id)
        XCTAssertEqual(persisted.count, 361)
        XCTAssertEqual(persisted.last?.elapsed, 1_800)
        let missing = try await store.samples(for: "nonexistent' OR 1=1 --")
        XCTAssertTrue(missing.isEmpty)
    }

    func testCorruptImportLeavesDatabaseEmpty() async throws {
        let root = temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ActivityStore(root: root)
        let file = root.appendingPathComponent("Broken.fit")
        try Data("not a FIT file".utf8).write(to: file)
        do { _ = try await store.importFile(file); XCTFail("Must reject invalid input") } catch {}
        let activities = try await store.activities()
        XCTAssertTrue(activities.isEmpty)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Originals").path).isEmpty)
    }

    func testTransactionRollsBackOnSampleFailure() async throws {
        let root = temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ActivityStore(root: root)
        let file = root.appendingPathComponent("Ride.fit")
        try DemoFIT.make().write(to: file)
        var connection: OpaquePointer?
        XCTAssertEqual(sqlite3_open(root.appendingPathComponent("training.sqlite").path, &connection), SQLITE_OK)
        defer { sqlite3_close(connection) }
        XCTAssertEqual(sqlite3_exec(connection, "CREATE TRIGGER fail_sample BEFORE INSERT ON samples BEGIN SELECT RAISE(ABORT, 'test failure'); END", nil, nil, nil), SQLITE_OK)
        do { _ = try await store.importFile(file); XCTFail("Must surface write failure") } catch {}
        let activities = try await store.activities()
        XCTAssertTrue(activities.isEmpty)
        XCTAssertEqual(sqlite3_exec(connection, "DROP TRIGGER fail_sample", nil, nil, nil), SQLITE_OK)
        let count = try await store.importFile(file)
        XCTAssertEqual(count, 1, "A failed transaction must be retryable")
    }

    func testRejectsNewerDatabaseSchema() throws {
        let root = temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var connection: OpaquePointer?
        XCTAssertEqual(sqlite3_open(root.appendingPathComponent("training.sqlite").path, &connection), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(connection, "PRAGMA user_version = 99", nil, nil, nil), SQLITE_OK)
        sqlite3_close(connection)
        XCTAssertThrowsError(try ActivityStore(root: root))
    }

    func testExportsStayInsideLibraryAndNeverOverwriteEachOther() async throws {
        let root = temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ActivityStore(root: root)
        let first = try await store.exportCSV("value\n1\n", suggestedName: "../../race.csv")
        let second = try await store.exportCSV("value\n2\n", suggestedName: "../../race.csv")
        XCTAssertEqual(first.deletingLastPathComponent(), root.appendingPathComponent("Exports", isDirectory: true))
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try String(contentsOf: first, encoding: .utf8), "value\n1\n")
        XCTAssertEqual(try String(contentsOf: second, encoding: .utf8), "value\n2\n")
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: first.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    private func temporary() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("TrainingHubTests-\(UUID().uuidString)") }
}
