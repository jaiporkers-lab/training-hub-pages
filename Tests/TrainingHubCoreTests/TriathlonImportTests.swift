import XCTest
import Foundation
import FITSwiftSDK
@testable import TrainingHubCore

final class TriathlonImportTests: XCTestCase, @unchecked Sendable {
    func testFiveLegTriathlonWithSharedSummaryTimestamp() throws {
        let decoded = try FITImporter.decode(fixture(), name: "Race")
        XCTAssertEqual(decoded.map(\.activity.sport), ["swimming", "transition", "cycling", "transition", "running"])
        XCTAssertEqual(decoded.map { $0.activity.laps.count }, [1, 1, 1, 1, 1])
        XCTAssertEqual(decoded.map { $0.samples.count }, [3, 0, 3, 0, 3])
        XCTAssertEqual(decoded[1].activity.title, "Race · 2. T1")
        XCTAssertEqual(decoded[3].activity.title, "Race · 4. T2")
        XCTAssertEqual(decoded[0].activity.elapsed, 90.775, accuracy: 0.001)
        XCTAssertEqual(decoded[2].samples.last?.elapsed, 120)
        XCTAssertEqual(decoded[2].activity.timer, 100.333)
        XCTAssertEqual(decoded[2].activity.elapsed, 120.333, accuracy: 0.001)
        XCTAssertTrue(decoded[1].samples.isEmpty, "Transitions need not contain sensor records")
    }

    func testSummaryFirstAndSummaryLastProduceSameLegs() throws {
        let first = try FITImporter.decode(fixture(summaryFirst: true), name: "Race")
        let last = try FITImporter.decode(fixture(), name: "Race")
        XCTAssertEqual(first.map(\.activity.start), last.map(\.activity.start))
        XCTAssertEqual(first.map(\.activity.elapsed), last.map(\.activity.elapsed))
        XCTAssertEqual(first.map { $0.samples.map(\.timestamp) }, last.map { $0.samples.map(\.timestamp) })
    }

    func testMissingSummaryTimestampStillUsesElapsedSpan() throws {
        let decoded = try FITImporter.decode(fixture(omitSummaryTimestamp: true), name: "Race")
        XCTAssertEqual(decoded.count, 5)
        XCTAssertEqual(decoded.last?.samples.last?.elapsed, 60)
    }

    func testLateSummaryDoesNotExtendLegPastItsElapsedSpan() throws {
        let decoded = try FITImporter.decode(fixture(lateSummary: true, extraRecordAfterFinish: true), name: "Race")
        XCTAssertEqual(decoded.last?.samples.count, 3)
        XCTAssertEqual(decoded.last?.samples.last?.elapsed, 60)
    }

    func testZeroDurationTransitionIsRetainedWithoutStealingBikeSamples() throws {
        let decoded = try FITImporter.decode(fixture(zeroTransition: true), name: "Race")
        XCTAssertEqual(decoded.count, 5)
        XCTAssertEqual(decoded[1].activity.elapsed, 0)
        XCTAssertTrue(decoded[1].samples.isEmpty)
        XCTAssertEqual(decoded[1].activity.laps.count, 1)
        XCTAssertEqual(decoded[2].samples.first?.elapsed, 0)
    }

    func testTimestampFallbackWhenElapsedIsAbsent() throws {
        let decoded = try FITImporter.decode(fixture(omitElapsed: true), name: "Race")
        XCTAssertEqual(decoded.count, 5)
        XCTAssertEqual(decoded[2].activity.elapsed, 120)
        XCTAssertEqual(decoded[2].samples.last?.elapsed, 120)
    }

    func testTriathlonPersistsEveryLegAndLap() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Triathlon-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ActivityStore(root: root)
        let file = root.appendingPathComponent("Race.fit")
        try fixture().write(to: file)
        let imported = try await store.importFile(file)
        XCTAssertEqual(imported, 5)
        let reopened = try ActivityStore(root: root)
        let activities = try await reopened.activities().sorted { $0.sessionIndex < $1.sessionIndex }
        XCTAssertEqual(activities.map(\.sport), ["swimming", "transition", "cycling", "transition", "running"])
        XCTAssertEqual(activities.map { $0.laps.count }, [1, 1, 1, 1, 1])
        for activity in activities {
            let samples = try await reopened.samples(for: activity.id)
            XCTAssertEqual(samples.count, activity.sampleCount)
        }
        let repeated = try await store.importFile(file)
        XCTAssertEqual(repeated, 0)
    }

    private func fixture(summaryFirst: Bool = false, omitSummaryTimestamp: Bool = false,
                         lateSummary: Bool = false, extraRecordAfterFinish: Bool = false,
                         zeroTransition: Bool = false, omitElapsed: Bool = false) throws -> Data {
        let start: UInt32 = 1_162_551_600
        let sports: [Sport] = [.swimming, .transition, .cycling, .transition, .running]
        let starts: [UInt32] = zeroTransition ? [0, 90, 90, 211, 216] : [0, 90, 105, 226, 231]
        let elapsed = [90.775, zeroTransition ? 0 : 15, 120.333, 5, 60.999]
        let encoder = Encoder()
        let file = FileIdMesg()
        try file.setType(.activity)
        try file.setTimeCreated(DateTime(timestamp: start))
        encoder.write(mesg: file)
        var summaries: [Mesg] = []
        var records: [Mesg] = []
        for index in sports.indices {
            let session = SessionMesg()
            try session.setMessageIndex(UInt16(index))
            try session.setSport(sports[index])
            try session.setStartTime(DateTime(timestamp: start + starts[index]))
            if !omitSummaryTimestamp {
                let stamp = omitElapsed ? start + starts[index] + UInt32(elapsed[index]) : start + (lateSummary ? 1_000 : 0)
                try session.setTimestamp(DateTime(timestamp: stamp))
            }
            if !omitElapsed { try session.setTotalElapsedTime(elapsed[index]) }
            try session.setTotalTimerTime(index == 2 ? 100.333 : elapsed[index])
            try session.setFirstLapIndex(UInt16(index))
            try session.setNumLaps(1)
            let lap = LapMesg()
            try lap.setMessageIndex(UInt16(index))
            try lap.setStartTime(DateTime(timestamp: start + starts[index]))
            try lap.setTimestamp(DateTime(timestamp: start))
            try lap.setTotalElapsedTime(elapsed[index])
            try lap.setTotalTimerTime(elapsed[index])
            summaries += [lap, session]
            if sports[index] != .transition {
                let offsets: [UInt32] = index == 2 ? [0, 60, 120] : [0, 30, 60]
                for offset in offsets {
                    let record = RecordMesg()
                    try record.setTimestamp(DateTime(timestamp: start + starts[index] + offset))
                    try record.setHeartRate(140)
                    records.append(record)
                }
            }
        }
        if extraRecordAfterFinish {
            let record = RecordMesg()
            try record.setTimestamp(DateTime(timestamp: start + 500))
            records.append(record)
        }
        encoder.write(mesgs: summaryFirst ? summaries + records : records + summaries)
        let activity = ActivityMesg()
        try activity.setTimestamp(DateTime(timestamp: start + 292))
        try activity.setNumSessions(5)
        encoder.write(mesg: activity)
        return encoder.close()
    }
}
