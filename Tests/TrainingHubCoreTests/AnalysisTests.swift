import XCTest
@testable import TrainingHubCore

final class AnalysisTests: XCTestCase {
    func testIrregularSamplingUsesTimeWeightsAndClipsIntervalEdges() {
        let samples = [sample(0, hr: 100), sample(1, hr: 200), sample(10, hr: 300)]
        let result = Analysis.summary(samples, metric: .heartRate, start: 0, end: 10)
        XCTAssertEqual(result.average!, 190, accuracy: 0.0001)
        XCTAssertEqual(result.minimum, 100)
        XCTAssertEqual(result.maximum, 300)
        XCTAssertEqual(result.coveredSeconds, 10)
        let clipped = Analysis.summary(samples, metric: .heartRate, start: 0.5, end: 5)
        XCTAssertEqual(clipped.average!, 850 / 4.5, accuracy: 0.0001)
        XCTAssertEqual(clipped.coveredSeconds, 4.5)
    }

    func testLongGapsAreExcludedEntirelyWithoutExtrapolatingTail() {
        let samples = [sample(0, power: 100), sample(10, power: 200), sample(100, power: 300), sample(110)]
        let result = Analysis.summary(samples, metric: .power, start: 0, end: 120)
        XCTAssertEqual(result.average, 200)
        XCTAssertEqual(result.coveredSeconds, 20)
        let zones = Analysis.zones(samples, metric: .power, boundaries: [150, 250], start: 0, end: 120)
        XCTAssertEqual(zones.bins.map(\.seconds), [10, 0, 10])
        XCTAssertEqual(zones.excludedSeconds, 100)
    }

    func testMissingAndZeroHRStayUncoveredWhileZeroPowerIsValid() {
        let samples = [sample(0, hr: 100, power: 0), sample(10), sample(20, hr: 0), sample(30, hr: 200)]
        XCTAssertEqual(Analysis.summary(samples, metric: .heartRate, start: 0, end: 30).coveredSeconds, 10)
        XCTAssertEqual(Analysis.summary(samples, metric: .power, start: 0, end: 30).average, 0)
        XCTAssertNil(Analysis.summary([sample(0)], metric: .power, start: 0, end: 10).average)
    }

    func testZoneThresholdsStartNextZoneAndDurationsUseElapsedCoverage() {
        let samples = [sample(0, hr: 99), sample(5, hr: 100), sample(15, hr: 150), sample(20, hr: 200), sample(25, hr: 200)]
        let result = Analysis.zones(samples, metric: .heartRate, boundaries: [100, 150, 200], start: 0, end: 25)
        XCTAssertEqual(result.bins.map(\.seconds), [5, 10, 5, 5])
        XCTAssertEqual(result.coveredSeconds, 25)
        XCTAssertEqual(result.excludedSeconds, 0)
        let clipped = Analysis.zones(samples, metric: .heartRate, boundaries: [100, 150, 200], start: 2, end: 17)
        XCTAssertEqual(clipped.bins.map(\.seconds), [3, 10, 2, 0])
    }

    func testZoneConfigurationValidation() throws {
        XCTAssertEqual(try Analysis.parseZoneBoundaries("120, 140; 160\n180"), [120, 140, 160, 180])
        for input in ["", "140,130", "140,140", "0,100", "nan", "inf", "100,nope", "1,2,3,4,5,6,7"] {
            XCTAssertThrowsError(try Analysis.parseZoneBoundaries(input), input)
        }
    }

    func testDistanceInterpolationIsBoundedAndDoesNotCrossGaps() {
        let samples = [sample(0, distance: 0), sample(10, distance: 100)]
        XCTAssertEqual(Analysis.interval(samples, start: 2, end: 8).distance, 60)
        XCTAssertNil(Analysis.interval(samples, start: -1, end: 8).distance)
        XCTAssertNil(Analysis.interval([sample(0, distance: 0), sample(100, distance: 1_000)], start: 2, end: 80).distance)
        XCTAssertNil(Analysis.interval([sample(0), sample(10, distance: 100)], start: 2, end: 8).distance)
    }

    func testPaceUsesMinutesPerKilometreAndRejectsStoppedSamples() {
        XCTAssertEqual(Metric.pace.value(sample(0, speed: 4))!, 25 / 6, accuracy: 0.0001)
        XCTAssertNil(Metric.pace.value(sample(0, speed: 0)))
        XCTAssertNil(Metric.pace.value(sample(0, speed: -1)))
        XCTAssertNil(Metric.pace.value(sample(0)))
    }

    func testSmoothingDoesNotBridgeMissingReadingsOrGaps() {
        let missing = [sample(0, power: 10), sample(1, power: 30), sample(2), sample(3, power: 100), sample(4, power: 300)]
        XCTAssertEqual(Analysis.smoothedValues(missing, metric: .power, window: 30), [20, 20, nil, 200, 200])
        let gaps = [sample(0, power: 10), sample(1, power: 30), sample(100, power: 100), sample(101, power: 300)]
        XCTAssertEqual(Analysis.smoothedValues(gaps, metric: .power, window: 30), [20, 20, 200, 200])
        XCTAssertEqual(Analysis.smoothedValues(missing, metric: .power, window: 0), [10, 30, nil, 100, 300])
    }

    func testSmoothingRespectsSportBoundaries() {
        let samples = [sample(0, power: 10), sample(1, power: 30), sample(2, power: 100), sample(3, power: 300)]
        XCTAssertEqual(Analysis.smoothedValues(samples, metric: .power, window: 30, breaks: [2]), [20, 20, 200, 200])
    }

    func testCSVKeepsMissingValuesBlankAndExcludesGPS() {
        let csv = CSVExport.samples([sample(0, hr: 150, power: 0)])
        XCTAssertFalse(csv.contains("latitude"))
        XCTAssertFalse(csv.contains("longitude"))
        XCTAssertTrue(csv.contains(",0.000,,150.000,,0.000,,,\n"))
        XCTAssertFalse(csv.contains("nan"))
        let lap = AnalysisLap(id: "lap", leg: "=untrusted", sport: "run, \"test\"", index: 1,
                              start: 0, end: 30, elapsed: 30, timer: 25, distance: 100)
        let laps = CSVExport.laps([lap])
        XCTAssertTrue(laps.contains("\"'=untrusted\",\"run, \"\"test\"\"\""))
        XCTAssertTrue(laps.contains("4.000"))
    }

    private func sample(_ elapsed: Double, hr: Double? = nil, power: Double? = nil,
                        distance: Double? = nil, speed: Double? = nil) -> Sample {
        Sample(id: Int(elapsed), timestamp: Date(timeIntervalSince1970: 1_700_000_000 + elapsed), elapsed: elapsed,
               distance: distance, heartRate: hr, speed: speed, power: power, cadence: nil, altitude: nil,
               temperature: nil, latitude: 12, longitude: 34)
    }
}
