import XCTest
import Foundation
@testable import TrainingHubCore

final class HistoryAndCleanupTests: XCTestCase, @unchecked Sendable {
    func testAllHistoryAutomaticallyContinuesBatchesAndDeduplicatesOverlap() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ActivityStore(root: root)
        let a = GarminActivity(id: "11", name: "A"), b = GarminActivity(id: "12", name: "B")
        let server = ScriptedGarmin([GarminTestData.token(), GarminTestData.list([a]), GarminTestData.zip(try DemoFIT.make()),
            GarminTestData.list([b]), GarminTestData.zip(try DemoFIT.make(variant: 1)), GarminTestData.list([b]), GarminTestData.list([])])
        let service = GarminSync(client: GarminClient(transport: server))
        let result = try await service.runAllHistory(store: store, apiKey: "test", maxPages: 2, pageSize: 1, progress: { _ in })
        XCTAssertTrue(result.completed); XCTAssertFalse(result.hasMoreHistory)
        XCTAssertEqual(result.imported, 2); XCTAssertEqual(result.duplicates, 1)
        XCTAssertEqual(result.failed, 0)
        let requests = await server.requests
        XCTAssertEqual(requests.filter { $0.url!.path.contains("download-service") }.count, 2)
        let rows = try await store.activities(); XCTAssertEqual(rows.count, 2)
    }
    func testNonAdvancingBatchStopsRatherThanLoopsForever() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ActivityStore(root: root)
        let a = GarminActivity(id: "11", name: "A")
        let server = ScriptedGarmin([GarminTestData.token(), GarminTestData.list([a]), GarminTestData.zip(try DemoFIT.make()), GarminTestData.list([a])])
        do {
            _ = try await GarminSync(client: GarminClient(transport: server)).runAllHistory(store: store, apiKey: "test", maxPages: 1, pageSize: 1, progress: { _ in })
            XCTFail("Must stop a non-advancing cursor")
        } catch { XCTAssertTrue(error.localizedDescription.contains("did not advance")) }
    }
    func testDemoCleanupPreservesRealActivitiesAndCreatesRecoverableBackup() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ActivityStore(root: root)
        let demo = root.appendingPathComponent("demo.fit"), real = root.appendingPathComponent("real.fit")
        try DemoFIT.make().write(to: demo); try DemoFIT.make(variant: 1).write(to: real)
        _ = try await store.importFile(demo, isDemo: true); _ = try await store.importFile(real)
        let before = try await store.activities(); let realID = try XCTUnwrap(before.first { !$0.isDemo }?.id)
        let backup = try await store.removeDemoActivities(); XCTAssertNotNil(backup)
        let after = try await store.activities(); XCTAssertEqual(after.map(\.id), [realID])
        let realSamples = try await store.samples(for: realID); XCTAssertFalse(realSamples.isEmpty)
        let again = try await store.removeDemoActivities(); XCTAssertNil(again)
        let manifest = try ActivityStore.inspectBackup(XCTUnwrap(backup)); XCTAssertEqual(manifest.originals.count, 2)
        _ = try await store.restoreBackup(XCTUnwrap(backup))
        let restored = try await store.activities(); XCTAssertEqual(restored.count, 2)
    }
}
