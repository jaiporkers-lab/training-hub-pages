import XCTest
import Foundation
import FITSwiftSDK
@testable import TrainingHubCore

final class RealFITTests: XCTestCase, @unchecked Sendable {
    func testLocalGarminZIPWhenProvided() throws {
        guard let path = ProcessInfo.processInfo.environment["TRAINING_HUB_TEST_ZIP"] else { throw XCTSkip("Set TRAINING_HUB_TEST_ZIP to verify an original local Garmin ZIP.") }
        let entries = try FITZip.read(Data(contentsOf: URL(fileURLWithPath: path)))
        XCTAssertEqual(entries.count, 1)
        let decoded = try FITImporter.decode(entries[0].data, name: "Local race")
        XCTAssertEqual(decoded.map(\.activity.sport), ["swimming", "transition", "cycling", "transition", "running"])
    }
    func testLocalRaceWhenProvided() async throws {
        guard let path = ProcessInfo.processInfo.environment["TRAINING_HUB_TEST_FIT"] else {
            throw XCTSkip("Set TRAINING_HUB_TEST_FIT to verify an original local race file; private files are never checked in.")
        }
        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url)
        let listener = FitListener()
        let decoder = FITSwiftSDK.Decoder(stream: FITSwiftSDK.InputStream(data: data))
        decoder.addMesgListener(listener)
        try decoder.read()
        let decoded = try FITImporter.decode(data, name: "Local race")
        XCTAssertEqual(decoded.count, listener.fitMessages.sessionMesgs.count)
        XCTAssertEqual(decoded.map(\.activity.sport), ["swimming", "transition", "cycling", "transition", "running"])
        XCTAssertEqual(decoded.map { $0.activity.laps.count }, [2, 1, 4, 1, 5])
        for item in decoded {
            XCTAssertGreaterThan(item.samples.count, 0)
            XCTAssertTrue(item.samples.allSatisfy { $0.elapsed >= 0 && $0.elapsed <= item.activity.elapsed })
            print("Verified race leg \(item.activity.sessionIndex + 1): \(item.activity.sport), \(item.samples.count) samples, \(item.activity.laps.count) laps")
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("RealRace-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ActivityStore(root: root)
        let count = try await store.importFile(url)
        XCTAssertEqual(count, 5)
        let reopened = try ActivityStore(root: root)
        let activities = try await reopened.activities()
        XCTAssertEqual(activities.count, 5)
        let groups = ActivityGroup.grouping(activities)
        XCTAssertEqual(groups.count, 1)
        let race = try XCTUnwrap(groups.first)
        XCTAssertEqual(race.summary.sport, "triathlon")
        XCTAssertEqual(race.summary.laps.count, 13)
        XCTAssertEqual(race.summary.sampleCount, 2_666)
        XCTAssertEqual(race.summary.elapsed, 3_982.094, accuracy: 0.001)
        let raceSamples = try await reopened.samples(for: race.id)
        XCTAssertEqual(raceSamples.count, 2_666)
        let heatmap = try await reopened.routeHeatmap(groups: groups, sport: nil)
        XCTAssertEqual(heatmap.activityCount, 1)
        XCTAssertGreaterThan(heatmap.activities.flatMap { $0 }.reduce(0) { $0 + $1.points.count }, 100)
        XCTAssertNotNil(heatmap.bounds)
        let bike = try await reopened.routeHeatmap(groups: groups, sport: "cycling")
        XCTAssertEqual(bike.activityCount, 1)
        let rawBike = try await reopened.routeHeatmap(groups: groups, sport: "cycling", trimIdle: false)
        XCTAssertEqual(bike.activities.first?.flatMap(\.points), rawBike.activities.first?.flatMap(\.points))
        XCTAssertLessThan(bike.activities.flatMap { $0 }.reduce(0) { $0 + $1.points.count },
                          heatmap.activities.flatMap { $0 }.reduce(0) { $0 + $1.points.count })
        XCTAssertEqual(Set(raceSamples.map(\.id)).count, 2_666)
        let laps = Analysis.laps(activity: race.summary, group: race)
        XCTAssertEqual(laps.count, 13)
        XCTAssertEqual(Set(laps.map(\.id)).count, 13)
        XCTAssertEqual(laps.filter { $0.leg == "Bike" }.count, 4)
        XCTAssertTrue(laps.allSatisfy { $0.start != nil && $0.end != nil })
        let heartRate = Analysis.summary(raceSamples, metric: .heartRate, start: 0, end: race.summary.elapsed)
        XCTAssertGreaterThan(heartRate.coveredSeconds, 3_000)
        XCTAssertLessThanOrEqual(heartRate.coveredSeconds, race.summary.elapsed)
        XCTAssertEqual(CSVExport.samples(raceSamples).split(separator: "\n").count, 2_667)
        for activity in activities {
            let samples = try await reopened.samples(for: activity.id)
            XCTAssertEqual(samples.count, activity.sampleCount)
        }
    }
}
