import XCTest
import Foundation
@testable import TrainingHubCore

final class ActivityGroupTests: XCTestCase, @unchecked Sendable {
    func testOneFeedActivityPerFileWithoutDoubleCountingLegs() throws {
        let multisport = try FITImporter.decode(DemoFIT.make(multisport: true), name: "Brick")
        let ride = try FITImporter.decode(DemoFIT.make(variant: 1), name: "Ride")
        let groups = ActivityGroup.grouping((multisport + ride).map(\.activity))
        XCTAssertEqual(groups.count, 2)
        let group = try XCTUnwrap(groups.first { $0.isMultisport })
        XCTAssertEqual(group.summary.title, "Brick")
        XCTAssertEqual(group.summary.sport, "multisport")
        XCTAssertEqual(group.summary.distance, 18_000)
        XCTAssertEqual(group.summary.timer, 3_600)
        XCTAssertEqual(group.summary.elapsed, 3_600)
        XCTAssertEqual(group.summary.sampleCount, 721)
        XCTAssertFalse(group.sessions.contains { $0.id == group.id })
        XCTAssertEqual(groups.reduce(0) { $0 + ($1.summary.distance ?? 0) }, 31_500)
    }

    func testCombinedClockDistanceAndUniqueSampleIDs() throws {
        let decoded = try FITImporter.decode(DemoFIT.make(multisport: true), name: "Brick")
        let group = ActivityGroup(sessions: decoded.map(\.activity))
        let samples = group.combinedSamples(decoded.map(\.samples))
        XCTAssertEqual(samples.count, 721)
        XCTAssertEqual(Set(samples.map(\.id)).count, 721)
        XCTAssertEqual(samples[360].elapsed, 1_800)
        XCTAssertEqual(samples[360].distance, 12_600)
        XCTAssertEqual(samples.last?.elapsed, 3_600)
        XCTAssertEqual(samples.last?.distance, 18_000)
        XCTAssertEqual(decoded[1].samples.first?.elapsed, 0, "Individual leg samples stay unchanged")
        XCTAssertEqual(decoded[1].samples.first?.distance, 0)
    }

    func testWholeActivityElapsedIncludesGapsWithoutAddingOverlapsTwice() throws {
        var sessions = try FITImporter.decode(DemoFIT.make(multisport: true), name: "Brick").map(\.activity)
        sessions[0].elapsed = 2_000
        XCTAssertEqual(ActivityGroup(sessions: sessions).summary.elapsed, 3_600)
        sessions[1].start = sessions[0].start.addingTimeInterval(2_400)
        let summary = ActivityGroup(sessions: sessions).summary
        XCTAssertEqual(summary.elapsed, 4_200)
        XCTAssertEqual(summary.timer, 3_600)
    }

    func testUnknownLegDistanceDoesNotInventCumulativeDistance() throws {
        let decoded = try FITImporter.decode(DemoFIT.make(multisport: true), name: "Brick")
        var sessions = decoded.map(\.activity)
        sessions[0].distance = nil
        sessions[0].avgPower = nil
        let group = ActivityGroup(sessions: sessions)
        XCTAssertNil(group.summary.distance)
        XCTAssertNil(group.summary.avgPower)
        let samples = group.combinedSamples(decoded.map(\.samples))
        XCTAssertNil(samples[360].distance)
        XCTAssertEqual(samples[360].elapsed, 1_800)
    }

    func testSummaryAveragesUseDurationWeightsAndRequireAllLegValues() throws {
        var sessions = try FITImporter.decode(DemoFIT.make(multisport: true), name: "Brick").map(\.activity)
        sessions[0].avgHeartRate = 100
        sessions[0].timer = 100
        sessions[1].avgHeartRate = 200
        sessions[1].timer = 300
        XCTAssertEqual(ActivityGroup(sessions: sessions).summary.avgHeartRate, 175)
        sessions[1].avgHeartRate = nil
        XCTAssertNil(ActivityGroup(sessions: sessions).summary.avgHeartRate)
    }

    func testSportFilterRetainsCompleteActivityAndLegs() throws {
        let sessions = try FITImporter.decode(DemoFIT.make(multisport: true), name: "Brick").map(\.activity)
        let group = ActivityGroup(sessions: sessions)
        XCTAssertTrue(group.matches(search: "", sport: "running"))
        XCTAssertTrue(group.matches(search: "Run", sport: "All sports"))
        XCTAssertTrue(group.matches(search: "Brick", sport: "cycling"))
        XCTAssertFalse(group.matches(search: "", sport: "swimming"))
        XCTAssertEqual(group.sessions.count, 2)
    }

    func testGroupSamplesLoadFromExistingDatabaseWithoutExtraActivityRows() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Group-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ActivityStore(root: root)
        let file = root.appendingPathComponent("Brick.fit")
        try DemoFIT.make(multisport: true).write(to: file)
        _ = try await store.importFile(file)
        let sessions = try await store.activities()
        let group = try XCTUnwrap(ActivityGroup.grouping(sessions).first)
        let samples = try await store.samples(for: group.id)
        XCTAssertEqual(samples.count, 721)
        XCTAssertEqual(samples.last?.distance, 18_000)
        let unchangedRows = try await store.activities()
        XCTAssertEqual(unchangedRows.count, 2)
        let reopened = try ActivityStore(root: root)
        let persisted = try await reopened.samples(for: group.id)
        XCTAssertEqual(persisted.count, 721)
    }
}
