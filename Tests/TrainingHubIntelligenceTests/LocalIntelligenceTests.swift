import XCTest
import TrainingHubCore
@testable import TrainingHubIntelligence

@MainActor
private final class ControlledGenerator: LocalHighlightGenerating {
    var calls = 0
    var availabilityCalls = 0
    var readiness: LocalAIAvailability = .ready
    var continuation: CheckedContinuation<[String], Error>?
    func availability() -> LocalAIAvailability { availabilityCalls += 1; return readiness }
    func select(from evidence: InsightEvidence) async throws -> [String] {
        calls += 1
        // Deliberately ignore cancellation to test late-result suppression and occupied slots.
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func finish(_ ids: [String] = ["overall.time"]) {
        continuation?.resume(returning: ids); continuation = nil
    }
}

@MainActor
final class LocalIntelligenceTests: XCTestCase {
    private func packet() throws -> InsightEvidence {
        var a = try FITImporter.decode(DemoFIT.make(), name: "Synthetic")[0].activity
        a.id = "a"; a.fileHash = "a"
        var b = a; b.id = "b"; b.fileHash = "b"
        return .comparison(selected: ActivityGroup.grouping([a])[0], baseline: ActivityGroup.grouping([b])[0], basis: .elapsed)
    }
    private func settings() -> UserDefaults {
        let name = "GarHub-AI-Test-\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: name) }
        return defaults
    }
    private func waitForCall(_ fake: ControlledGenerator) async {
        for _ in 0..<100 where fake.calls == 0 { await Task.yield() }
        XCTAssertEqual(fake.calls, 1)
    }
    private func settle() async { for _ in 0..<30 { await Task.yield() } }

    func testDefaultOffDoesNotQueryOrRunModelAndOptInPersists() throws {
        let fake = ControlledGenerator(), defaults = settings()
        let model = LocalIntelligence(defaults: defaults, generator: fake, timeout: .seconds(20))
        model.highlight(try packet())
        XCTAssertFalse(model.enabled); XCTAssertEqual(model.availability, .off)
        XCTAssertEqual(fake.calls, 0); XCTAssertEqual(fake.availabilityCalls, 0)
        model.enabled = true
        XCTAssertTrue(defaults.bool(forKey: LocalIntelligence.enabledKey))
        model.enabled = false
        XCTAssertFalse(defaults.bool(forKey: LocalIntelligence.enabledKey))
    }
    func testOffClearsResultAndLateCancelledResultCannotReappear() async throws {
        let fake = ControlledGenerator()
        let active = LocalIntelligence(defaults: settings(), generator: fake, timeout: .seconds(20))
        active.enabled = true; active.highlight(try packet()); await waitForCall(fake)
        active.enabled = false
        XCTAssertFalse(active.isRunning); XCTAssertNil(active.evidence); XCTAssertTrue(active.selectedIDs.isEmpty)
        fake.finish(); await settle()
        XCTAssertNil(active.evidence); XCTAssertTrue(active.selectedIDs.isEmpty)
        active.enabled = true; active.highlight(try packet()); await settle()
        XCTAssertEqual(fake.calls, 2) // Cancelled backend released its slot.
        fake.finish(); await settle()
        XCTAssertEqual(active.selectedIDs, ["overall.time"])
        active.enabled = false
        XCTAssertTrue(active.selectedIDs.isEmpty)
    }
    func testCancellationPreventsOverlappingBackendAndStaleSelection() async throws {
        let fake = ControlledGenerator()
        let active = LocalIntelligence(defaults: settings(), generator: fake, timeout: .seconds(20))
        active.enabled = true; active.highlight(try packet()); await waitForCall(fake)
        active.cancel(); active.highlight(try packet())
        XCTAssertEqual(fake.calls, 1); XCTAssertTrue(active.selectedIDs.isEmpty)
        fake.finish(); await settle()
        XCTAssertTrue(active.selectedIDs.isEmpty)
        active.highlight(try packet()); await settle(); XCTAssertEqual(fake.calls, 2)
        fake.finish(["invented"]); await settle()
        XCTAssertTrue(active.selectedIDs.isEmpty)
        XCTAssertTrue(active.message.contains("couldn't be completed"))
    }
    func testUnavailableModelDoesNotStartGeneration() throws {
        let fake = ControlledGenerator(); fake.readiness = .unavailable("Not ready")
        let model = LocalIntelligence(defaults: settings(), generator: fake, timeout: .seconds(20))
        model.enabled = true; model.highlight(try packet())
        XCTAssertEqual(fake.calls, 0); XCTAssertFalse(model.isRunning)
        XCTAssertEqual(model.message, "Not ready")
    }
    func testDeadlineUpdatesImmediatelyEvenIfBackendIgnoresCancellation() async throws {
        let fake = ControlledGenerator()
        let active = LocalIntelligence(defaults: settings(), generator: fake, timeout: .milliseconds(10))
        active.enabled = true; active.highlight(try packet()); await waitForCall(fake)
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertFalse(active.isRunning); XCTAssertTrue(active.message.contains("too long"))
        fake.finish(); await settle()
        XCTAssertTrue(active.selectedIDs.isEmpty)
    }
}
