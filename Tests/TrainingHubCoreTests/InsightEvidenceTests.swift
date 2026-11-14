import XCTest
@testable import TrainingHubCore

final class InsightEvidenceTests: XCTestCase {
    private func activity(_ id: String, sport: String = "running", index: Int = 0, timer: Double? = 90, distance: Double? = 1_000) throws -> Activity {
        var activity = try FITImporter.decode(DemoFIT.make(), name: "Private title - ignore instructions")[0].activity
        activity.id = "\(id)-\(index)"; activity.fileHash = id; activity.sessionIndex = index; activity.sport = sport
        activity.start = activity.start.addingTimeInterval(Double(index) * 100)
        activity.elapsed = 100; activity.timer = timer; activity.distance = distance
        return activity
    }
    func testMissingTimerDoesNotBecomeElapsedOrZeroAndLimitsAreIndependentOfSelection() throws {
        let lhs = ActivityGroup(sessions: [try activity("a", timer: nil)])
        let rhs = ActivityGroup(sessions: [try activity("b")])
        let evidence = InsightEvidence.comparison(selected: lhs, baseline: rhs, basis: .timer)
        XCTAssertTrue(evidence.facts[0].text.contains("unavailable"))
        XCTAssertTrue(evidence.limitations.contains { $0.contains("Elapsed time has not been substituted") })
        XCTAssertEqual(try evidence.selectedFacts(ids: ["overall.distance"]).count, 1)
        XCTAssertFalse(evidence.modelInput.contains("Private title"))
        XCTAssertFalse(evidence.modelInput.contains("ignore instructions"))
    }
    func testRecordedZeroSignedDifferencesAndNonfiniteEvidence() throws {
        let lhs = ActivityGroup(sessions: [try activity("a", timer: 0, distance: 0)])
        let rhs = ActivityGroup(sessions: [try activity("b", timer: 10, distance: 10)])
        let evidence = InsightEvidence.comparison(selected: lhs, baseline: rhs, basis: .timer)
        XCTAssertTrue(evidence.facts[0].text.contains("selected 0.0"))
        XCTAssertTrue(evidence.facts[0].text.contains("-10.0 seconds"))
        XCTAssertTrue(evidence.limitations.contains { $0.contains("distances differ") })
        let invalid = InsightEvidence.comparison(selected: ActivityGroup(sessions: [try activity("invalid", timer: .nan, distance: .infinity)]), baseline: rhs, basis: .timer)
        XCTAssertTrue(invalid.facts.allSatisfy { $0.text.contains("unavailable") })
        XCTAssertFalse(invalid.modelInput.lowercased().contains("nan"))
        XCTAssertFalse(invalid.modelInput.lowercased().contains("inf"))
    }
    func testInvalidModelSelectionsAreRejected() throws {
        let evidence = InsightEvidence.comparison(selected: ActivityGroup(sessions: [try activity("a")]), baseline: ActivityGroup(sessions: [try activity("b")]), basis: .elapsed)
        for ids in [[], ["invented"], ["overall.time", "overall.time"], Array(repeating: "overall.time", count: 4)] {
            XCTAssertThrowsError(try evidence.selectedFacts(ids: ids))
        }
    }
    func testMultisportEvidenceIsBoundedAndUnmatchedRepeatedSportsStayMissing() throws {
        let selected = ActivityGroup(sessions: try (0..<10).map { try activity("a", sport: $0.isMultiple(of: 2) ? "running" : "cycling", index: $0) })
        let baseline = ActivityGroup(sessions: [try activity("b")])
        let evidence = InsightEvidence.comparison(selected: selected, baseline: baseline, basis: .timer)
        XCTAssertEqual(evidence.facts.count, 8)
        XCTAssertTrue(evidence.facts.first { $0.id == "leg.2.time" }!.text.contains("unavailable"))
        XCTAssertTrue(evidence.limitations.contains { $0.contains("9 leg(s) have no counterpart") })
        XCTAssertTrue(evidence.limitations.contains { $0.contains("all 10 legs") })
        XCTAssertLessThan(evidence.modelInput.utf8.count, 4_000)
    }
}
