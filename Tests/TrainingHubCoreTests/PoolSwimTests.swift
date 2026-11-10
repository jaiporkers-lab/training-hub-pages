import Foundation
import FITSwiftSDK
import XCTest
@testable import TrainingHubCore

final class PoolSwimTests: XCTestCase {
    func testLengthsRetainRecordedFieldsAndBelongToTheirSwimSession() throws {
        let data = try fixture()
        let first = try XCTUnwrap(FITImporter.poolSwim(data, sessionIndex: 0))
        XCTAssertEqual(first.lengthMeters, 25)
        XCTAssertEqual(first.lengths.map(\.startOffset), [0, 20, 30])
        XCTAssertEqual(first.lengths.map(\.kind), [.swim, .rest, .unknown])
        XCTAssertEqual(first.lengths.map(\.swolf), [36, nil, nil])
        XCTAssertEqual(first.lengths.first?.stroke, "Freestyle")
        XCTAssertEqual(first.lengths.first?.elapsed, 20)
        XCTAssertEqual(first.lengths.first?.timer, 18.5)
        XCTAssertEqual(first.lengths.first?.pacePer100Meters(poolLength: first.lengthMeters), 74)
        XCTAssertNil(try FITImporter.poolSwim(data, sessionIndex: 1))
        let second = try XCTUnwrap(FITImporter.poolSwim(data, sessionIndex: 2))
        XCTAssertEqual(second.lengths.map(\.startOffset), [0])
        XCTAssertNil(second.lengthMeters)
        XCTAssertNil(second.lengths[0].pacePer100Meters(poolLength: second.lengthMeters))
        XCTAssertNil(second.lengths[0].swolf)
    }

    func testLocalPoolRecordingWhenProvided() throws {
        guard let path = ProcessInfo.processInfo.environment["TRAINING_HUB_TEST_POOL"] else {
            throw XCTSkip("Set TRAINING_HUB_TEST_POOL to a local pool FIT recording.")
        }
        let data = try FITImporter.readFile(URL(fileURLWithPath: path))
        let index = try XCTUnwrap(FITImporter.decode(data, name: "Pool").first { $0.activity.sport == "swimming" }?.activity.sessionIndex)
        let swim = try XCTUnwrap(FITImporter.poolSwim(data, sessionIndex: index))
        XCTAssertGreaterThan(swim.lengths.filter { $0.kind == .swim }.count, 0)
        XCTAssertTrue(swim.lengths.contains { $0.swolf != nil })
    }

    private func fixture() throws -> Data {
        let encoder = Encoder()
        let timestamp: UInt32 = 1_162_551_600
        let file = FileIdMesg()
        try file.setType(.activity)
        encoder.write(mesg: file)
        func session(_ offset: UInt32, sport: Sport, pool: Double? = nil) throws {
            let row = SessionMesg()
            try row.setStartTime(DateTime(timestamp: timestamp + offset))
            try row.setTotalElapsedTime(40)
            try row.setSport(sport)
            if let pool { try row.setPoolLength(pool) }
            encoder.write(mesg: row)
        }
        func length(_ offset: UInt32, kind: LengthType? = nil, strokes: UInt16? = nil) throws {
            let row = LengthMesg()
            try row.setStartTime(DateTime(timestamp: timestamp + offset))
            try row.setTotalElapsedTime(20)
            try row.setTotalTimerTime(18.5)
            if let kind { try row.setLengthType(kind) }
            if let strokes {
                try row.setTotalStrokes(strokes)
                try row.setSwimStroke(.freestyle)
            }
            encoder.write(mesg: row)
        }
        try length(0, kind: .active, strokes: 17)
        try length(20, kind: .idle, strokes: 2)
        try length(30, strokes: 9)
        try length(40, kind: .active, strokes: 13)
        try length(80, kind: .active)
        try session(80, sport: .swimming)
        try session(0, sport: .swimming, pool: 25)
        try session(40, sport: .transition)
        return encoder.close()
    }
}
