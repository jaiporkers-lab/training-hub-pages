import XCTest
@testable import TrainingHubCore

final class NewAnalysisTests: XCTestCase {
    private func sample(_ t: Double, distance: Double? = nil, hr: Double? = nil, power: Double? = nil, speed: Double? = nil, altitude: Double? = nil, lat: Double? = 1, lon: Double? = 1) -> Sample {
        Sample(id: Int(t * 10), timestamp: Date(timeIntervalSince1970: t + 1_700_000_000), elapsed: t,
               distance: distance, heartRate: hr, speed: speed, power: power, cadence: nil, altitude: altitude,
               temperature: nil, latitude: lat, longitude: lon)
    }
    func testPowerCurveTimeWeightsPreservesZeroAndRejectsGaps() throws {
        let data = [sample(0, power: 100), sample(4, power: 400), sample(10, power: 0), sample(15, power: 0)]
        let curve = try PerformanceAnalysis.powerCurve(data, durations: [5, 10, 15, 16])
        XCTAssertEqual(curve[0].watts!, 400, accuracy: 0.0001)
        XCTAssertEqual(curve[1].watts!, 280, accuracy: 0.0001)
        XCTAssertEqual(curve[2].watts!, 2_800 / 15.0, accuracy: 0.0001)
        XCTAssertNil(curve[3].watts)
        XCTAssertEqual(try PerformanceAnalysis.powerCurve([sample(0, power: 0), sample(5, power: 0)], durations: [5])[0].watts, 0)
        XCTAssertNil(try PerformanceAnalysis.powerCurve([sample(0, power: 500), sample(60, power: 500)], durations: [5])[0].watts)
        XCTAssertNil(try PerformanceAnalysis.powerCurve([sample(0, power: 500), sample(2), sample(10, power: 500)], durations: [5])[0].watts)
    }
    func testDistanceEffortsIncludeInternalPausesAndInterpolateBoundaries() throws {
        let data = [sample(0, distance: 0), sample(20, distance: 200), sample(40, distance: 200), sample(60, distance: 400)]
        let effort = try PerformanceAnalysis.bestDistanceEfforts(data, distances: [100, 300, 400])
        XCTAssertEqual(effort[0].seconds!, 10, accuracy: 0.001)
        XCTAssertEqual(effort[1].seconds!, 50, accuracy: 0.001)
        XCTAssertEqual(effort[2].seconds!, 60, accuracy: 0.001)
        let gap = [sample(0, distance: 0), sample(90, distance: 1_000)]
        XCTAssertNil(try PerformanceAnalysis.bestDistanceEfforts(gap, distances: [400])[0].seconds)
        let reset = [sample(0, distance: 0), sample(10, distance: 100), sample(20, distance: 0), sample(30, distance: 100)]
        XCTAssertNil(try PerformanceAnalysis.bestDistanceEfforts(reset, distances: [200])[0].seconds)
    }
    func testSplitsKeepPartialAndDoNotBridgeMissingDistance() {
        let data = (0...25).map { sample(Double($0 * 20), distance: Double($0 * 100), hr: 150) }
        let splits = PerformanceAnalysis.runningSplits(data)
        XCTAssertEqual(splits.map(\.meters), [1_000, 1_000, 500])
        XCTAssertEqual(splits[0].secondsPerKilometer, 200)
        XCTAssertEqual(splits[0].heartRateCoverage, 1)
        var missing = data; missing[5].distance = nil
        XCTAssertEqual(PerformanceAnalysis.runningSplits(missing).map(\.number), [2, 3])
    }
    func testDriftRequiresCoveredHalvesAndTenMinutes() {
        let data = (0...120).map { index in sample(Double(index * 10), hr: index < 60 ? 150 : 165, speed: 3) }
        let steady = PerformanceAnalysis.steadyEffort(data, start: 0, end: 1_200)
        XCTAssertEqual(steady.coverage, 1)
        XCTAssertEqual(steady.driftPercent!, (1 - 150 / 165.0) * 100, accuracy: 0.0001)
        XCTAssertEqual(steady.paceVariationPercent!, 0, accuracy: 0.0001)
        XCTAssertNil(PerformanceAnalysis.steadyEffort(data, start: 0, end: 500).driftPercent)
        var missing = data
        for index in 0..<40 { missing[index].heartRate = nil }
        XCTAssertNil(PerformanceAnalysis.steadyEffort(missing, start: 0, end: 1_200).driftPercent)
    }
    func testCalendarRoundTripValidationAndDSTMoveRetainsClock() throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Australia/Sydney")!
        let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: 7, minute: 30))!
        let next = calendar.date(byAdding: .day, value: 1, to: start)!
        let plan = TrainingPlan(title: "Easy run", date: start, sport: "running", minutes: 45, kind: .workout)
        let moved = plan.moved(to: next, calendar: calendar)
        XCTAssertEqual(calendar.component(.hour, from: moved.date), 7)
        XCTAssertEqual(moved.date.timeIntervalSince(plan.date), 23 * 3_600)
        XCTAssertEqual(try TrainingPlan.decode(TrainingPlan.encode([moved])), [moved])
        XCTAssertThrowsError(try TrainingPlan.encode([plan, plan]))
        var invalid = plan; invalid.minutes = -1
        XCTAssertThrowsError(try TrainingPlan.encode([invalid]))
        invalid = plan; invalid.title = "   "
        XCTAssertThrowsError(try TrainingPlan.encode([invalid]))
    }
    func testRecoveryMissingDaysStayMissingAndNextDayAssociationExcludesToday() throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1))!
        let now = calendar.date(byAdding: .day, value: 20, to: start)!
        let formatter = HealthAnalysis.formatter(); formatter.timeZone = calendar.timeZone
        let template = try FITImporter.decode(DemoFIT.make(), name: "Synthetic")[0].activity
        let activities = (0..<20).map { index -> Activity in
            var activity = template; activity.id = "\(index)"; activity.fileHash = "\(index)"; activity.isDemo = false
            activity.start = calendar.date(byAdding: .day, value: index, to: start)!; activity.timer = Double((index + 1) * 60)
            return activity
        }
        let health = (0..<20).map { index in HealthDay(day: formatter.string(from: calendar.date(byAdding: .day, value: index, to: start)!), source: .hrv, values: ["hrv": Double(index + 10)]) }
        let metric = HealthMetric.all.first { $0.id == "hrv" }!
        let report = RecoveryTrends.make(activities: activities + [activities[0]], health: health, metric: metric, days: 28, lag: 1, now: now, calendar: calendar)
        XCTAssertEqual(report.pairs, 20)
        XCTAssertEqual(report.association!, 1, accuracy: 0.0001)
        XCTAssertEqual(report.recentDays, 7)
        XCTAssertEqual(report.previousDays, 13)
        XCTAssertNil(report.points[0].health)
        XCTAssertEqual(report.points.last?.trainingMinutes, 20)
        let empty = RecoveryTrends.make(activities: [], health: health, metric: metric, days: 28, now: now, calendar: calendar)
        XCTAssertNil(empty.association)
    }
    func testRouteTrackBreaksInvalidFixesAndJumpsAndClimbsNeedCoverage() throws {
        let data = [sample(0), sample(5, lat: 1.00001), sample(10, lat: nil), sample(15, lat: 1.00003), sample(20, lat: 20)]
        let points = try RouteAnalysis.vertices(data, metric: .heartRate)
        XCTAssertEqual(points.count, 4)
        XCTAssertEqual(points[0].segment, points[1].segment)
        XCTAssertNotEqual(points[1].segment, points[2].segment)
        XCTAssertNotEqual(points[2].segment, points[3].segment)
        let hill: [Sample] = (0...60).map { (index: Int) -> Sample in
            let t = Double(index) * 5
            let meters = Double(index) * 20
            let height = Double(index) * 2
            let latitude = 1.0 + Double(index) * 0.0001
            return sample(t, distance: meters, altitude: height, lat: latitude)
        }
        let climbs = RouteAnalysis.climbs(hill)
        XCTAssertEqual(climbs.count, 1)
        XCTAssertGreaterThan(climbs[0].gain, 100)
        let signature = try RouteAnalysis.signature(hill, size: 100)
        XCTAssertEqual(RouteAnalysis.overlap(signature, signature), 1)
        let distant = try RouteAnalysis.signature(hill.map { point in var copy = point; copy.latitude = 30; return copy }, size: 100)
        XCTAssertEqual(RouteAnalysis.overlap(signature, distant), 0)
    }
}
