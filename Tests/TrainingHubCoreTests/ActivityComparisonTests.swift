import XCTest
import Foundation
@testable import TrainingHubCore

final class ActivityComparisonTests: XCTestCase {
    private func race(_ prefix: String, sports: [String]) throws -> [Activity] {
        let prototype = try FITImporter.decode(DemoFIT.make(), name: "Race")[0].activity
        return sports.enumerated().map { index, sport in
            var item = prototype
            item.id = "\(prefix)-\(index)"; item.fileHash = prefix; item.sessionIndex = index; item.sport = sport
            item.start = prototype.start.addingTimeInterval(Double(index * 100))
            item.elapsed = 100; item.timer = 90; item.distance = 1000
            return item
        }
    }
    func testTriathlonMatchesBothTransitionsAndKeepsSignedDifferences() throws {
        let sports = ["swimming", "transition", "cycling", "transition", "running"]
        let baseline = try race("b", sports: sports)
        var selected = try race("a", sports: sports)
        selected[1].elapsed = 80; selected[3].elapsed = 120
        selected[2].distance = 1100
        let rows = ActivityComparison.legs(selected: ActivityGroup(sessions: selected), baseline: ActivityGroup(sessions: baseline))
        XCTAssertEqual(rows.map(\.title), ["Swim", "T1", "Bike", "T2", "Run"])
        XCTAssertEqual(rows[1].elapsedDifference, -20); XCTAssertEqual(rows[3].elapsedDifference, 20)
        XCTAssertEqual(rows[2].distanceDifference, 100)
        XCTAssertEqual(Set(rows.map(\.id)).count, 5)
    }
    func testMissingSportDoesNotShiftLaterLegMatches() throws {
        let selected = try race("a", sports: ["swimming", "transition", "cycling", "transition", "running"])
        let baseline = try race("b", sports: ["transition", "cycling", "transition", "running"])
        let rows = ActivityComparison.legs(selected: ActivityGroup(sessions: selected), baseline: ActivityGroup(sessions: baseline))
        XCTAssertNil(rows[0].baseline); XCTAssertNil(rows[0].elapsedDifference)
        XCTAssertEqual(rows[2].baseline?.sport, "cycling")
        XCTAssertEqual(rows[4].baseline?.sport, "running")
        XCTAssertEqual(rows[3].baseline?.sessionIndex, 2)
    }
    func testRepeatedSportsHaveDistinctOccurrencesAndUnmatchedLegsAreRetained() throws {
        let selected = try race("a", sports: ["running", "cycling", "running"])
        let baseline = try race("b", sports: ["running", "cycling", "running", "cycling"])
        let rows = ActivityComparison.legs(selected: ActivityGroup(sessions: selected), baseline: ActivityGroup(sessions: baseline))
        XCTAssertEqual(rows.map(\.id), ["running:0", "cycling:0", "running:1", "cycling:1"])
        XCTAssertEqual(rows[2].title, "Run 2"); XCTAssertNil(rows[3].selected)
        XCTAssertEqual(rows[2].baseline?.sessionIndex, 2)
    }
    func testMissingTimerNeverFallsBackToElapsedAndZeroIsPreserved() throws {
        var selected = try race("a", sports: ["cycling"])
        var baseline = try race("b", sports: ["cycling"])
        selected[0].timer = nil; selected[0].distance = nil
        baseline[0].elapsed = 0
        let row = ActivityComparison.legs(selected: ActivityGroup(sessions: selected), baseline: ActivityGroup(sessions: baseline))[0]
        XCTAssertNil(row.timerDifference); XCTAssertNil(row.distanceDifference)
        XCTAssertEqual(row.elapsedDifference, 100)
        selected[0].timer = 0; baseline[0].timer = 0
        XCTAssertEqual(ActivityComparison.legs(selected: ActivityGroup(sessions: selected), baseline: ActivityGroup(sessions: baseline))[0].timerDifference, 0)
    }
}
