import XCTest
import Foundation
@testable import TrainingHubCore

final class SampleInspectionIndexTests: XCTestCase {
    private func sample(_ index: Int, elapsed: Double, distance: Double? = nil) -> Sample {
        Sample(id: index, timestamp: Date(timeIntervalSince1970: elapsed), elapsed: elapsed, distance: distance,
               heartRate: nil, speed: nil, power: nil, cadence: nil, altitude: nil, temperature: nil, latitude: nil, longitude: nil)
    }
    func testNearestTimeBoundariesToleranceAndSourceOrderTies() {
        let data = [sample(0, elapsed: 0), sample(1, elapsed: 60), sample(2, elapsed: 60), sample(3, elapsed: 120)]
        let index = SampleInspectionIndex(samples: data)
        XCTAssertEqual(index.nearest(to: 0, tolerance: 0), 0)
        XCTAssertEqual(index.nearest(to: 1, tolerance: 0), 1)
        XCTAssertEqual(index.nearest(to: 1.5, tolerance: 0.5), 1)
        XCTAssertEqual(index.nearest(to: 2, tolerance: 0), 3)
        XCTAssertNil(index.nearest(to: 10, tolerance: 0.5))
        XCTAssertNil(index.nearest(to: .nan, tolerance: 1))
        XCTAssertNil(index.nearest(to: .infinity, tolerance: 1))
        XCTAssertNil(index.nearest(to: 1, tolerance: -1))
        XCTAssertNil(SampleInspectionIndex().nearest(to: 0, tolerance: 1))
    }
    func testDistanceRegressionsMissingValuesAndDuplicatesPreserveOriginalSamples() {
        let data = [sample(0, elapsed: 0, distance: 2000), sample(1, elapsed: 1, distance: nil),
                    sample(2, elapsed: 2, distance: 1000), sample(3, elapsed: 3, distance: 2000), sample(4, elapsed: 4, distance: .nan)]
        let index = SampleInspectionIndex(samples: data, distanceAxis: true)
        XCTAssertEqual(index.nearest(to: 1, tolerance: 0), 2)
        XCTAssertEqual(index.nearest(to: 2.01, tolerance: 0.05), 0)
        XCTAssertEqual(index.nearest(to: 1.5, tolerance: 0.5), 0, "Equidistant readings retain earliest source order")
        XCTAssertNil(index.nearest(to: 1.2, tolerance: 0.05))
        XCTAssertNil(data[2].heartRate, "Indexing must not invent a missing sensor value")
        XCTAssertEqual(data[0].distance, 2000)
    }
    func testIndexedResultsAgreeWithFullScanAcrossLargeIrregularRecording() {
        let data = (0..<10_000).map { sample($0, elapsed: Double($0 * 3), distance: $0 % 11 == 0 ? nil : Double(($0 * 17) % 21_001)) }
        for distanceAxis in [false, true] {
            let index = SampleInspectionIndex(samples: data, distanceAxis: distanceAxis)
            for query in 0..<100 {
                let target = Double(query * 137 % (distanceAxis ? 20_000 : 29_997)) / (distanceAxis ? 1000 : 60)
                let tolerance = distanceAxis ? 0.05 : 0.5
                let candidates = data.enumerated().compactMap { offset, reading -> (Int, Double)? in
                    let axis = distanceAxis ? reading.distance.map { $0 / 1000 } : reading.elapsed / 60
                    guard let axis else { return nil }
                    return (offset, abs(axis - target))
                }
                let reference = candidates.min { $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 < $1.1 }
                let expected = reference.flatMap { $0.1 <= tolerance ? $0.0 : nil }
                XCTAssertEqual(index.nearest(to: target, tolerance: tolerance), expected)
            }
        }
    }
}
