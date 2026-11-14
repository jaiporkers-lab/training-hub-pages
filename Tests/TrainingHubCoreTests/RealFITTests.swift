import XCTest
import Foundation
@testable import TrainingHubCore

final class RealFITTests: XCTestCase, @unchecked Sendable {
    func testLocalGarminZIPWhenProvided() throws {
        guard let path = ProcessInfo.processInfo.environment["TRAINING_HUB_TEST_ZIP"] else { throw XCTSkip("Set TRAINING_HUB_TEST_ZIP to a local reproduction archive.") }
        let entries = try FITZip.read(Data(contentsOf: URL(fileURLWithPath: path)))
        XCTAssertFalse(entries.isEmpty)
        for entry in entries {
            let decoded = try FITImporter.decode(entry.data, name: "Local recording")
            XCTAssertFalse(decoded.isEmpty)
            XCTAssertTrue(decoded.allSatisfy { $0.activity.elapsed >= 0 })
        }
    }
    func testLocalRaceWhenProvided() async throws {
        guard let path = ProcessInfo.processInfo.environment["TRAINING_HUB_TEST_FIT"] else { throw XCTSkip("Set TRAINING_HUB_TEST_FIT to a local recording. Private files are never checked in.") }
        let url = URL(fileURLWithPath: path)
        let decoded = try FITImporter.decode(Data(contentsOf: url), name: "Local recording")
        XCTAssertFalse(decoded.isEmpty)
        for item in decoded {
            XCTAssertTrue(item.samples.allSatisfy { $0.elapsed >= 0 && $0.elapsed <= item.activity.elapsed })
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LocalRecording-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ActivityStore(root: root)
        let imported = try await store.importFile(url)
        XCTAssertEqual(imported, decoded.count)
        let reopened = try ActivityStore(root: root)
        let activities = try await reopened.activities()
        XCTAssertEqual(activities.count, decoded.count)
        XCTAssertEqual(ActivityGroup.grouping(activities).count, 1)
        for activity in activities {
            let samples = try await reopened.samples(for: activity.id)
            XCTAssertEqual(samples.count, activity.sampleCount)
        }
    }
}
