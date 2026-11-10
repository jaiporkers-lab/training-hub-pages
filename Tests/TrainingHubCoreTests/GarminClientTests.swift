import XCTest
import Foundation
@testable import TrainingHubCore

actor ScriptedGarmin: GarminTransport {
    var responses: [GarminHTTPResponse]
    var requests: [URLRequest] = []
    init(_ responses: [GarminHTTPResponse]) { self.responses = responses }
    func send(_ request: URLRequest) async throws -> GarminHTTPResponse {
        requests.append(request)
        guard !responses.isEmpty else { throw HubError.message("Unexpected test request") }
        return responses.removeFirst()
    }
}
actor RetryDelays { var values: [Double] = []; func add(_ value: Double) { values.append(value) } }

private actor GarminZIPMediaTypeServer: GarminTransport {
    let archive: Data
    init(archive: Data) { self.archive = archive }
    func send(_ request: URLRequest) async throws -> GarminHTTPResponse {
        if request.httpMethod == "POST" { return GarminTestData.token() }
        let accepted = (request.value(forHTTPHeaderField: "Accept") ?? "").split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        // Garmin's published download response uses this distinct ZIP media type.
        guard accepted.contains("application/x-zip-compressed") else { return .init(data: Data(), status: 406) }
        return .init(data: archive, status: 200, headers: ["content-type": "application/x-zip-compressed"])
    }
}

enum GarminTestData {
    static func token(_ marker: Int = 1, exp: Double = 2_000_000_000) -> GarminHTTPResponse {
        let payload = try! JSONSerialization.data(withJSONObject: ["exp": exp, "marker": Double(marker)])
        let encoded = payload.base64EncodedString().replacingOccurrences(of: "=", with: "").replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        return GarminHTTPResponse(data: Data("header.\(encoded).signature".utf8), status: 200)
    }
    static func list(_ values: [GarminActivity]) -> GarminHTTPResponse { GarminHTTPResponse(data: try! JSONEncoder().encode(values), status: 200) }
    static func zip(_ data: Data) -> GarminHTTPResponse { GarminHTTPResponse(data: ZIPFixture.make(data, deflated: true), status: 200) }
}

final class GarminClientTests: XCTestCase, @unchecked Sendable {
    func testDownloadNegotiatesPublishedZIPTypeInsteadOf406() async throws {
        let archive = ZIPFixture.make(try DemoFIT.make(), deflated: true)
        let client = GarminClient(transport: GarminZIPMediaTypeServer(archive: archive))
        let downloaded = try await client.download(apiKey: "unit-test-key", activityID: "123")
        XCTAssertEqual(downloaded, archive)
        XCTAssertEqual(try FITZip.read(downloaded).count, 1)
    }
    func testOfficialTokenExchangeCachingAndChildExclusion() async throws {
        let server = ScriptedGarmin([GarminTestData.token(), GarminTestData.list([]), GarminTestData.list([])])
        let client = GarminClient(transport: server)
        try await client.verify(apiKey: "unit-test-key")
        try await client.verify(apiKey: "unit-test-key")
        let requests = await server.requests
        XCTAssertEqual(requests.count, 3)
        XCTAssertEqual(requests[0].httpMethod, "POST")
        XCTAssertEqual(requests[0].url?.path, "/personalapitoken-service/personal-api/personal-api-key/token")
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Authorization"), "ApiKey unit-test-key")
        XCTAssertTrue(requests.allSatisfy { $0.url?.host == "personal.connectapi.garmin.com" && $0.url?.scheme == "https" })
        let query = URLComponents(url: requests[1].url!, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(query.first { $0.name == "excludeChildren" }?.value, "true")
        XCTAssertTrue(requests[1].value(forHTTPHeaderField: "Authorization")!.hasPrefix("Bearer "))
    }
    func testRejectsNonGarminOriginsBeforeSendingAnyCredentials() async throws {
        let server = ScriptedGarmin([])
        let client = GarminClient(transport: server)
        for destination in ["http://personal.connectapi.garmin.com", "https://example.com",
                            "https://personal.connectapi.garmin.com:8443", "https://user@personal.connectapi.garmin.com"] {
            let url = try XCTUnwrap(URL(string: destination))
            do {
                _ = try await client.authorized(apiKey: "test-key", url: url, accept: "application/json")
                XCTFail("Must reject an unexpected Garmin origin")
            } catch {
                XCTAssertEqual(error.localizedDescription, "The Garmin destination is not allowed.")
            }
        }
        let requests = await server.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func test401RefreshesTokenExactlyOnce() async throws {
        let server = ScriptedGarmin([GarminTestData.token(1), .init(data: Data(), status: 401), GarminTestData.token(2), GarminTestData.list([])])
        try await GarminClient(transport: server).verify(apiKey: "test")
        let requests = await server.requests
        XCTAssertEqual(requests.count, 4)
        XCTAssertNotEqual(requests[1].value(forHTTPHeaderField: "Authorization"), requests[3].value(forHTTPHeaderField: "Authorization"))
    }
    func testBoundedRetryAndLongRetryAfterStopsWithoutHammering() async throws {
        let delays = RetryDelays()
        let server = ScriptedGarmin([GarminTestData.token(), .init(data: Data(), status: 503), GarminTestData.list([])])
        let client = GarminClient(transport: server, sleep: { await delays.add($0) })
        try await client.verify(apiKey: "test")
        let waited = await delays.values
        XCTAssertEqual(waited, [1])
        let limited = ScriptedGarmin([GarminTestData.token(), .init(data: Data("private body".utf8), status: 429, headers: ["retry-after": "120"])])
        do { try await GarminClient(transport: limited, sleep: { _ in XCTFail("Must not retry before a long Retry-After") }).verify(apiKey: "test"); XCTFail() }
        catch { XCTAssertFalse(error.localizedDescription.contains("private body")) }
        let limitedRequests = await limited.requests
        XCTAssertEqual(limitedRequests.count, 2)
    }
    func testChangedKeyDoesNotReuseOldTokenAndExpiredTokenIsRejected() async throws {
        let server = ScriptedGarmin([GarminTestData.token(1), GarminTestData.list([]), GarminTestData.token(2), GarminTestData.list([])])
        let client = GarminClient(transport: server)
        try await client.verify(apiKey: "first"); try await client.verify(apiKey: "second")
        let requests = await server.requests
        XCTAssertEqual(requests.filter { $0.httpMethod == "POST" }.count, 2)
        let expired = ScriptedGarmin([GarminTestData.token(exp: 100)])
        do { try await GarminClient(transport: expired).verify(apiKey: "secret-test-value"); XCTFail() }
        catch { XCTAssertFalse(error.localizedDescription.contains("secret-test-value")) }
    }
    func testNumericIDsAndInvalidIdentifiers() throws {
        let values = try JSONDecoder().decode([GarminActivity].self, from: Data("[{\"activityId\":123,\"activityName\":\"Race\",\"parentId\":0},{\"activityId\":\"124\",\"parentId\":123}]".utf8))
        XCTAssertEqual(values.map(\.id), ["123", "124"])
        XCTAssertNil(values[0].parentID); XCTAssertEqual(values[1].parentID, "123")
        for value in ["true", "-1", "0", "\"../secret\""] { XCTAssertThrowsError(try JSONDecoder().decode(GarminActivity.self, from: Data("{\"activityId\":\(value)}".utf8))) }
    }
}
