import XCTest
import Foundation
@testable import TrainingHubCore

final class GarminSyncTests: XCTestCase, @unchecked Sendable {
    func testCancellationDoesNotMarkAnUnfinishedDownloadImportedOrAdvanceHistory() async throws {
        actor SlowServer: GarminTransport {
            var downloadStarted = false
            func send(_ request: URLRequest) async throws -> GarminHTTPResponse {
                if request.httpMethod == "POST" { return GarminTestData.token() }
                if request.url!.path.contains("activitylist-service") { return GarminTestData.list([GarminActivity(id: "50", name: "Cancel test")]) }
                downloadStarted = true
                try await Task.sleep(for: .seconds(30))
                return .init(data: Data(), status: 200)
            }
        }
        let root = temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try ActivityStore(root: root)
        let server = SlowServer()
        let service = GarminSync(client: GarminClient(transport: server))
        let task = Task { try await service.run(store: store, apiKey: "test", history: true, pageSize: 1, progress: { _ in }) }
        for _ in 0..<200 {
            if await server.downloadStarted { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        task.cancel()
        do { _ = try await task.value; XCTFail("Must cancel") } catch { XCTAssertTrue(error is CancellationError) }
        let rows = try await store.activities()
        XCTAssertTrue(rows.isEmpty)
        let offset = try await store.syncValue("garmin." + FITImporter.hash(Data("test".utf8)) + ".historyOffset")
        XCTAssertNil(offset)
        let pending = try await store.pendingGarminActivities(scope: "garmin." + FITImporter.hash(Data("test".utf8)))
        XCTAssertTrue(pending.isEmpty)
    }
    func testMultisportParentIsImportedOnceAndRepeatedSyncSkipsDownload() async throws {
        let root = temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try ActivityStore(root: root)
        let data = try DemoFIT.make(multisport: true)
        let records = [GarminActivity(id: "1", name: "My triathlon"), GarminActivity(id: "2", name: "Child", parentID: "1")]
        let server = ScriptedGarmin([GarminTestData.token(), GarminTestData.list(records), GarminTestData.zip(data), GarminTestData.list(records)])
        let service = GarminSync(client: GarminClient(transport: server))
        let first = try await service.run(store: store, apiKey: "test", history: false, pageSize: 3, progress: { _ in })
        XCTAssertEqual(first.imported, 1)
        let activities = try await store.activities()
        XCTAssertEqual(activities.count, 2)
        XCTAssertEqual(ActivityGroup.grouping(activities).count, 1)
        XCTAssertEqual(ActivityGroup.grouping(activities)[0].summary.title, "My triathlon")
        let second = try await service.run(store: store, apiKey: "test", history: false, pageSize: 3, progress: { _ in })
        XCTAssertEqual(second.imported, 0); XCTAssertEqual(second.duplicates, 1)
        let requests = await server.requests
        XCTAssertEqual(requests.filter { $0.url!.path.contains("download-service") }.count, 1)
    }

    func testHistoryResumesWithOnePageOverlapAndNoRepeatedDownloads() async throws {
        let root = temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try ActivityStore(root: root)
        let firstPage = [GarminActivity(id: "10", name: "A"), GarminActivity(id: "11", name: "B")]
        let finalPage = [GarminActivity(id: "12", name: "C")]
        let server = ScriptedGarmin([GarminTestData.token(), GarminTestData.list(firstPage),
            GarminTestData.zip(try DemoFIT.make()), GarminTestData.zip(try DemoFIT.make(variant: 1)),
            GarminTestData.list(firstPage), GarminTestData.list(finalPage), GarminTestData.zip(try DemoFIT.make(variant: 2))])
        let service = GarminSync(client: GarminClient(transport: server))
        let first = try await service.run(store: store, apiKey: "test", history: true, maxPages: 1, pageSize: 2, progress: { _ in })
        XCTAssertTrue(first.hasMoreHistory); XCTAssertFalse(first.completed)
        let second = try await service.run(store: store, apiKey: "test", history: true, maxPages: 2, pageSize: 2, progress: { _ in })
        XCTAssertFalse(second.hasMoreHistory); XCTAssertTrue(second.completed)
        XCTAssertEqual(second.imported, 1); XCTAssertEqual(second.duplicates, 2)
        let activities = try await store.activities()
        XCTAssertEqual(activities.count, 3)
        let requests = await server.requests
        XCTAssertEqual(requests.filter { $0.url!.path.contains("download-service") }.count, 3)
    }

    func testFailedFITIsQueuedAndRetriedWithoutBlockingValidActivities() async throws {
        let root = temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try ActivityStore(root: root)
        let page = [GarminActivity(id: "20", name: "Needs retry"), GarminActivity(id: "21", name: "Valid")]
        let server = ScriptedGarmin([GarminTestData.token(), GarminTestData.list(page),
            GarminTestData.zip(Data("not FIT".utf8)), GarminTestData.zip(try DemoFIT.make()),
            GarminTestData.zip(try DemoFIT.make(variant: 1)), GarminTestData.list(page)])
        let service = GarminSync(client: GarminClient(transport: server))
        let first = try await service.run(store: store, apiKey: "test", history: false, pageSize: 3, progress: { _ in })
        XCTAssertEqual(first.failed, 1); XCTAssertEqual(first.imported, 1)
        let scope = "garmin." + FITImporter.hash(Data("test".utf8))
        let pending = try await store.pendingGarminActivities(scope: scope)
        XCTAssertEqual(pending.map(\.id), ["20"])
        let otherAccount = try await store.pendingGarminActivities(scope: "different-key")
        XCTAssertTrue(otherAccount.isEmpty)
        let second = try await service.run(store: store, apiKey: "test", history: false, pageSize: 3, progress: { _ in })
        XCTAssertEqual(second.failed, 0); XCTAssertEqual(second.imported, 1)
        let remaining = try await store.pendingGarminActivities(scope: scope)
        XCTAssertTrue(remaining.isEmpty)
    }

    func testRateLimitStopsTheRunAndDoesNotAdvanceHistoryCursor() async throws {
        let root = temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try ActivityStore(root: root)
        let page = [GarminActivity(id: "30", name: "A"), GarminActivity(id: "31", name: "B")]
        let server = ScriptedGarmin([GarminTestData.token(), GarminTestData.list(page), .init(data: Data(), status: 429, headers: ["retry-after": "120"])])
        let service = GarminSync(client: GarminClient(transport: server))
        do { _ = try await service.run(store: store, apiKey: "test", history: true, pageSize: 2, progress: { _ in }); XCTFail() }
        catch { XCTAssertTrue(error is GarminError) }
        let requests = await server.requests
        XCTAssertEqual(requests.count, 3)
        let offset = try await store.syncValue("garmin." + FITImporter.hash(Data("test".utf8)) + ".historyOffset")
        XCTAssertNil(offset)
    }

    func testManualOriginalAndCustomNameSurviveGarminSync() async throws {
        let root = temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try ActivityStore(root: root)
        let data = try DemoFIT.make()
        let file = root.appendingPathComponent("Manual.fit"); try data.write(to: file)
        _ = try await store.importFile(file)
        try await store.renameActivity(fileHash: FITImporter.hash(data), title: "My custom race name")
        let server = ScriptedGarmin([GarminTestData.token(), GarminTestData.list([GarminActivity(id: "40", name: "Garmin name")]), GarminTestData.zip(data)])
        let result = try await GarminSync(client: GarminClient(transport: server)).run(store: store, apiKey: "test", history: false, progress: { _ in })
        XCTAssertEqual(result.duplicates, 1)
        let activities = try await store.activities()
        XCTAssertEqual(activities.count, 1); XCTAssertEqual(activities[0].title, "My custom race name")
    }

    private func temporary() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("GarminSyncTests-\(UUID().uuidString)") }
}
