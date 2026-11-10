import Foundation
import XCTest
@testable import TrainingHubCore

final class ActivityGraphTests: XCTestCase {
    func testGraphSplitsAtMissingValuesLegsGapsAndDistanceResets() {
        let samples = [
            sample(0, 0, 120), sample(1, 10, 121), sample(2, 20, nil), sample(3, 30, 123),
            sample(4, 40, 124), sample(5, 50, 125), sample(6, 0, 126), sample(45, 10, 127)
        ]
        let points = ActivityGraph.points(samples, metric: .heartRate, distanceAxis: true, smoothing: 0,
                                          breaks: [4], swimPace: false)
        XCTAssertEqual(points.map(\.id), [0, 1, 3, 4, 5, 6, 7])
        XCTAssertEqual(points.map(\.segment), [0, 0, 1, 2, 2, 3, 4])
        XCTAssertEqual(points.map(\.x), [0, 0.01, 0.03, 0.04, 0.05, 0, 0.01])
    }

    func testPreferredMetricFindsSharedRecordingAndIgnoresInvalidHeartRate() {
        let left = [sample(0, 0, 150, speed: 3)]
        let right = [sample(0, 0, 0, speed: 2)]
        XCTAssertEqual(ActivityGraph.preferredMetric(.heartRate, selected: left, baseline: right), .speed)
        XCTAssertEqual(ActivityGraph.preferredMetric(.heartRate, selected: right, baseline: []), .speed)
        let swim = ActivityGraph.points(right, metric: .pace, distanceAxis: false, smoothing: 0,
                                        breaks: [], swimPace: true)
        XCTAssertEqual(swim[0].y, 50 / 60, accuracy: 0.000_001)
    }

    func testDenseGraphKeepsSpikesEndpointsAndSeparateLegs() {
        var samples = (0..<10_000).map { sample(Double($0), Double($0), 140) }
        samples[5_003].heartRate = 205
        samples[5_004].heartRate = 90
        let raw = ActivityGraph.points(samples, metric: .heartRate, distanceAxis: false, smoothing: 0,
                                       breaks: [3_333], swimPace: false)
        let plotted = ActivityGraph.displayPoints(raw)
        let ids = plotted.map(\.id)
        XCTAssertLessThan(plotted.count, 2_010)
        XCTAssertEqual(ids, ids.sorted())
        XCTAssertTrue(Set([0, 3_332, 3_333, 5_003, 5_004, 9_999]).isSubset(of: ids))
        XCTAssertEqual(Set(plotted.map(\.segment)), [0, 1])
    }

    private func sample(_ seconds: Double, _ distance: Double, _ hr: Double?, speed: Double? = nil) -> Sample {
        Sample(id: Int(seconds), timestamp: Date(timeIntervalSinceReferenceDate: seconds), elapsed: seconds,
               distance: distance, heartRate: hr, speed: speed, power: nil, cadence: nil, altitude: nil,
               temperature: nil, latitude: nil, longitude: nil)
    }
}
