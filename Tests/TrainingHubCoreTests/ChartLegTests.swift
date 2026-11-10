import XCTest
import Foundation
@testable import TrainingHubCore

final class ChartLegTests: XCTestCase {
    private func sessions() throws -> [Activity] {
        let prototype = try FITImporter.decode(DemoFIT.make(), name: "Race")[0].activity
        let sports = ["swimming", "transition", "cycling", "transition", "running"]
        let starts: [Double] = [0, 60, 70, 190, 200]
        let durations: [Double] = [60, 10, 120, 10, 90]
        let distances: [Double] = [100, 5, 1000, 5, 500]
        return sports.indices.map { index in
            var leg = prototype
            leg.id = "leg-\(index)"; leg.sessionIndex = index; leg.sport = sports[index]
            leg.start = prototype.start.addingTimeInterval(starts[index])
            leg.elapsed = durations[index]; leg.distance = distances[index]
            return leg
        }
    }
    func testElapsedInspectionIdentifiesTransitionsAndExactBoundaries() throws {
        let group = ActivityGroup(sessions: try sessions())
        let positions: [Double] = [0, 59, 60, 69, 70, 189, 190, 199, 200, 290]
        XCTAssertEqual(positions.map { group.leg(at: $0).map(group.legName) },
                       ["Swim", "Swim", "T1", "T1", "Bike", "Bike", "T2", "T2", "Run", "Run"])
        for invalid in [-1.0, 291, .nan, .infinity] { XCTAssertNil(group.leg(at: invalid)) }
    }
    func testDistanceInspectionUsesLegTotalsAndPreservesUnknowns() throws {
        var legs = try sessions()
        let group = ActivityGroup(sessions: legs)
        XCTAssertEqual([0.0, 100, 105, 1105, 1110, 1610].map { group.leg(at: $0, distance: true).map(group.legName) },
                       ["Swim", "T1", "Bike", "T2", "Run", "Run"])
        legs[1].distance = nil
        let unknown = ActivityGroup(sessions: legs)
        XCTAssertEqual(unknown.leg(at: 99, distance: true)?.sport, "swimming")
        XCTAssertNil(unknown.leg(at: 101, distance: true))
    }
    func testGapsOverlapsAndZeroDurationLegs() throws {
        var legs = try sessions()
        legs[2].start = legs[0].start.addingTimeInterval(80)
        XCTAssertNil(ActivityGroup(sessions: legs).leg(at: 75))
        legs[2].start = legs[0].start.addingTimeInterval(65)
        XCTAssertEqual(ActivityGroup(sessions: legs).leg(at: 67)?.sport, "cycling")
        legs[1].elapsed = 0
        legs[2].start = legs[0].start.addingTimeInterval(60)
        XCTAssertEqual(ActivityGroup(sessions: legs).leg(at: 60)?.sport, "cycling")
    }
}
