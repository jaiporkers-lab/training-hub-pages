import XCTest
import Foundation
@testable import TrainingHubCore

final class HealthAndCoachTests: XCTestCase, @unchecked Sendable {
    func testDocumentedSchemasUnitsMissingValuesAndPrivacy() throws {
        let daily = try HealthAnalysis.decode(Data(#"{"data":[{"calendarDate":"2026-11-01","heartRate":{"restingValue":48},"movement":{"steps":{"value":0}},"stress":{"avgLevel":-1},"hydration":{"consumedInFractionalMl":1500},"calories":{"burnedActive":true},"userProfilePk":123,"note":"private"},{"calendarDate":"2026-02-31","heartRate":{"restingValue":50}}]}"#.utf8), source: .daily)
        XCTAssertEqual(daily.count, 1); XCTAssertEqual(daily[0].values["rhr"], 48)
        XCTAssertEqual(daily[0].values["steps"], 0); XCTAssertEqual(daily[0].values["water"], 1.5)
        XCTAssertNil(daily[0].values["stress"]); XCTAssertNil(daily[0].values["activeCalories"])
        let sleep = try HealthAnalysis.decode(Data(#"[{"calendarDate":"2026-11-01","sleepTimeSeconds":27000,"userNote":"private"}]"#.utf8), source: .sleep)
        XCTAssertEqual(sleep[0].values["sleep"], 7.5)
        let hrv = try HealthAnalysis.decode(Data(#"{"hrvSummaries":[{"calendarDate":"2026-11-01","lastNightAvg":57}]}"#.utf8), source: .hrv)
        XCTAssertEqual(hrv[0].values["hrv"], 57)
        let weight = try HealthAnalysis.decode(Data(#"{"dailyWeightSummaries":[{"summaryDate":"2026-11-01","latestWeight":{"weight":72.5}}]}"#.utf8), source: .weight)
        XCTAssertEqual(weight[0].values["weight"], 72.5, "Published endpoint supplies kilograms")
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(daily + sleep), as: UTF8.self).contains("private"))
        XCTAssertThrowsError(try HealthAnalysis.decode(Data("{}".utf8), source: .daily))
        XCTAssertTrue(try HealthAnalysis.decode(Data(), source: .hrv).isEmpty)
    }
    func testCompletedDayComparisonsUseAvailableValuesAndExcludeToday() throws {
        let now = try XCTUnwrap(HealthAnalysis.date("2026-11-08"))
        let rows = [HealthDay(day: "2026-11-07", source: .daily, values: ["rhr": 50]),
                    HealthDay(day: "2026-11-06", source: .daily, values: [:]),
                    HealthDay(day: "2026-11-08", source: .daily, values: ["rhr": 100]),
                    HealthDay(day: "2026-10-31", source: .daily, values: ["rhr": 60])]
        let result = HealthAnalysis.compare(rows, metric: HealthMetric.all[0], days: 7, now: now)
        XCTAssertEqual(result.current, 50); XCTAssertEqual(result.previous, 60)
        XCTAssertEqual(result.currentCount, 1); XCTAssertEqual(result.previousCount, 1)
        XCTAssertNil(HealthAnalysis.compare([], metric: HealthMetric.all[0], days: 7, now: now).current)
    }
    func testHealthClientRoutesAndThirtyOneDayBounds() async throws {
        let response = GarminHTTPResponse(data: Data(#"{"data":[]}"#.utf8), status: 200)
        let server = ScriptedGarmin([GarminTestData.token(), response, .init(data: Data(), status: 204)])
        let client = GarminClient(transport: server)
        _ = try await client.health(apiKey: "test", source: .daily, from: "2026-10-01", to: "2026-10-31")
        _ = try await client.health(apiKey: "test", source: .hrv, from: "2026-10-01", to: "2026-10-31")
        let requests = await server.requests
        XCTAssertEqual(requests[1].url?.path, "/usersummary-service/v2/dailysummaries")
        XCTAssertEqual(requests[2].url?.path, "/hrv-service/hrv/daily/2026-10-01/2026-10-31")
        for from in ["../secret", "2026-10-00", "2026-09-01"] {
            do { _ = try await client.health(apiKey: "test", source: .sleep, from: from, to: "2026-10-31"); XCTFail() } catch {}
        }
    }
    func testHealthCacheReplacementPersistenceAndBackup() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ActivityStore(root: root)
        try await store.saveHealth([.init(day: "2026-11-01", source: .daily, values: ["rhr": 50])], source: .daily, from: "2026-11-01", to: "2026-11-01")
        try await store.saveHealth([.init(day: "2026-11-01", source: .sleep, values: ["sleep": 8])], source: .sleep, from: "2026-11-01", to: "2026-11-01")
        let backup = try await store.createBackup()
        try await store.saveHealth([], source: .daily, from: "2026-11-01", to: "2026-11-01")
        let cache = try await store.healthCache(); XCTAssertEqual(cache.days.count, 1); XCTAssertEqual(cache.days[0].source, .sleep)
        _ = try await store.restoreBackup(backup)
        let reopened = try ActivityStore(root: root); let restored = try await reopened.healthCache()
        XCTAssertEqual(restored.days.count, 2)
    }
    func testCoachBriefIsBoundedAndHealthIsOptIn() throws {
        var items = try FITImporter.decode(DemoFIT.make(), name: "PRIVATE ROUTE NAME").map(\.activity)
        items[0].isDemo = false; items[0].start = Date().addingTimeInterval(-3600)
        let brief = CoachBrief.make(activities: items, health: [], goal: String(repeating: "x", count: 2000), includeHealth: false)
        XCTAssertFalse(brief.contains("PRIVATE ROUTE NAME")); XCTAssertFalse(brief.contains("OPTIONAL HEALTH"))
        XCTAssertFalse(brief.contains(String(repeating: "x", count: 1001))); XCTAssertLessThan(brief.count, 6000)
        XCTAssertTrue(CoachBrief.make(activities: items, health: [], goal: "Triathlon", includeHealth: true).contains("OPTIONAL HEALTH"))
    }
    func testRecordedStatsDecodeEverySessionWithUnitsAndRejectCorruption() throws {
        let stats = try FITImporter.sessionStats(DemoFIT.make(multisport: true))
        XCTAssertEqual(stats.count, 2)
        let distance = try XCTUnwrap(stats[0].stats.first { $0.id == "fit:9" })
        XCTAssertEqual(distance.unit, "m"); XCTAssertEqual(Double(distance.value), 12600)
        XCTAssertTrue(stats[0].stats.contains { $0.id == "fit:16" && $0.unit == "bpm" })
        XCTAssertThrowsError(try FITImporter.sessionStats(Data("invalid".utf8)))
    }
}
