import Foundation

public struct GarminActivity: Codable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let parentID: String?
    enum CodingKeys: String, CodingKey { case id = "activityId", name = "activityName", parentID = "parentId" }
    public init(id: String, name: String, parentID: String? = nil) { self.id = id; self.name = name; self.parentID = parentID }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let id: String
        if let text = try? values.decode(String.self, forKey: .id) { id = text }
        else { id = try values.decode(Int64.self, forKey: .id).description }
        guard Self.validID(id) else { throw HubError.message("Garmin returned an invalid activity identifier.") }
        self.id = id
        name = String((try values.decodeIfPresent(String.self, forKey: .name) ?? "Garmin activity \(id)").prefix(200))
        if let parent = try? values.decode(Int64.self, forKey: .parentID), parent > 0 { parentID = String(parent) }
        else if let parent = try? values.decode(String.self, forKey: .parentID), Self.validID(parent) { parentID = parent }
        else { parentID = nil }
    }
    static func validID(_ value: String) -> Bool { !value.isEmpty && value.count <= 30 && value.utf8.allSatisfy { (48...57).contains($0) } && value.contains { $0 != "0" } }
}

public struct GarminHTTPResponse: Sendable {
    public let data: Data
    public let status: Int
    public let headers: [String: String]
    public init(data: Data, status: Int, headers: [String: String] = [:]) { self.data = data; self.status = status; self.headers = headers }
}
public protocol GarminTransport: Sendable { func send(_ request: URLRequest) async throws -> GarminHTTPResponse }

private final class NoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

public final class GarminURLTransport: GarminTransport, @unchecked Sendable {
    private let session: URLSession
    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30; config.timeoutIntervalForResource = 90
        config.httpShouldSetCookies = false; config.urlCache = nil
        session = URLSession(configuration: config, delegate: NoRedirects(), delegateQueue: nil)
    }
    public func send(_ request: URLRequest) async throws -> GarminHTTPResponse {
        let (file, response) = try await session.download(for: request)
        defer { try? FileManager.default.removeItem(at: file) }
        guard let response = response as? HTTPURLResponse else { throw HubError.message("Garmin returned an invalid network response.") }
        var headers: [String: String] = [:]
        for (key, value) in response.allHeaderFields { headers[String(describing: key).lowercased()] = String(describing: value) }
        return GarminHTTPResponse(data: try FITImporter.readFile(file), status: response.statusCode, headers: headers)
    }
}

public enum GarminError: LocalizedError, Sendable {
    case http(Int)
    public var errorDescription: String? {
        switch self {
        case .http(401), .http(403): "Garmin rejected the credential or its permissions. Check the Personal API key and expiry in Garmin Connect."
        case .http(429): "Garmin is limiting requests. Sync has paused; try again later."
        case .http(let status): "Garmin returned HTTP \(status). Your existing activities remain available locally."
        }
    }
}

public actor GarminClient {
    private let transport: any GarminTransport
    private let clock: @Sendable () -> Date
    private let sleep: @Sendable (Double) async throws -> Void
    private var cachedToken: (fingerprint: String, token: String, expiry: Date)?
    private var credentialGeneration = 0
    private let base = URL(string: "https://personal.connectapi.garmin.com")!

    public init(transport: any GarminTransport = GarminURLTransport(), clock: @escaping @Sendable () -> Date = { Date() },
                sleep: @escaping @Sendable (Double) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }) {
        self.transport = transport; self.clock = clock; self.sleep = sleep
    }
    public func disconnect() { cachedToken = nil; credentialGeneration += 1 }

    public func verify(apiKey: String) async throws {
        _ = try await activities(apiKey: apiKey, offset: 0, limit: 1, startDate: nil, endDate: nil)
    }

    public func activities(apiKey: String, offset: Int, limit: Int = 50, startDate: String?, endDate: String?) async throws -> [GarminActivity] {
        guard offset >= 0, (1...99).contains(limit) else { throw HubError.message("The requested Garmin page is invalid.") }
        var query = [URLQueryItem(name: "start", value: String(offset)), URLQueryItem(name: "limit", value: String(limit)),
                     URLQueryItem(name: "excludeChildren", value: "true"), URLQueryItem(name: "sortOrder", value: "desc"),
                     URLQueryItem(name: "sortBy", value: "startLocal")]
        if let startDate { query.append(URLQueryItem(name: "startDate", value: startDate)) }
        if let endDate { query.append(URLQueryItem(name: "endDate", value: endDate)) }
        var url = URLComponents(url: base.appendingPathComponent("activitylist-service/activities/search/activities"), resolvingAgainstBaseURL: false)!
        url.queryItems = query
        let response = try await authorized(apiKey: apiKey, url: url.url!, accept: "application/json")
        return try JSONDecoder().decode([GarminActivity].self, from: response.data)
    }

    public func download(apiKey: String, activityID: String) async throws -> Data {
        guard GarminActivity.validID(activityID) else { throw HubError.message("The Garmin activity identifier is invalid.") }
        let response = try await authorized(apiKey: apiKey, url: base.appendingPathComponent("download-service/files/activity/\(activityID)"), accept: "application/zip, application/x-zip-compressed, application/octet-stream")
        guard !response.data.isEmpty else { throw HubError.message("Garmin returned an empty activity download.") }
        return response.data
    }

    func authorized(apiKey: String, url: URL, accept: String) async throws -> GarminHTTPResponse {
        try requireGarminOrigin(url)
        for attempt in 0...1 {
            let token = try await token(apiKey: apiKey)
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue(accept, forHTTPHeaderField: "Accept")
            let response = try await requestWithRetry(request)
            if response.status == 401 && attempt == 0 { cachedToken = nil; continue }
            guard (200..<300).contains(response.status) else { throw GarminError.http(response.status) }
            return response
        }
        throw GarminError.http(401)
    }

    private func token(apiKey: String) async throws -> String {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !key.contains("\r"), !key.contains("\n"), key.count < 10_000 else { throw HubError.message("Enter a valid Personal API key in the app.") }
        let fingerprint = FITImporter.hash(Data(key.utf8))
        let generation = credentialGeneration
        if let cachedToken, cachedToken.fingerprint == fingerprint, cachedToken.expiry.timeIntervalSince(clock()) > 300 { return cachedToken.token }
        var request = URLRequest(url: base.appendingPathComponent("personalapitoken-service/personal-api/personal-api-key/token"))
        request.httpMethod = "POST"
        request.setValue("ApiKey \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        let response = try await requestWithRetry(request)
        guard generation == credentialGeneration else { throw CancellationError() }
        guard (200..<300).contains(response.status) else { throw GarminError.http(response.status) }
        guard let token = String(data: response.data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), token.count < 32_000 else {
            throw HubError.message("Garmin did not return a usable access token.")
        }
        let pieces = token.split(separator: ".")
        guard pieces.count == 3 else { throw HubError.message("Garmin returned an unsupported access-token format.") }
        var payload = String(pieces[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        struct Expiry: Decodable { let exp: Double }
        guard let bytes = Data(base64Encoded: payload), let claim = try? JSONDecoder().decode(Expiry.self, from: bytes),
              claim.exp.isFinite, claim.exp > clock().timeIntervalSince1970 else { throw HubError.message("Garmin returned an expired or unrecognised access token.") }
        cachedToken = (fingerprint, token, Date(timeIntervalSince1970: claim.exp))
        return token
    }

    private func requireGarminOrigin(_ url: URL?) throws {
        guard let url, url.scheme == base.scheme, url.host == base.host,
              url.port == nil || url.port == 443, url.user == nil, url.password == nil else {
            throw HubError.message("The Garmin destination is not allowed.")
        }
    }

    private func requestWithRetry(_ request: URLRequest) async throws -> GarminHTTPResponse {
        // Fixed host and no redirects keep credentials on Garmin's documented service.
        try requireGarminOrigin(request.url)
        for attempt in 0...2 {
            try Task.checkCancellation()
            let response = try await transport.send(request)
            guard response.data.count <= FITImporter.maximumFileSize else { throw HubError.message("The Garmin response exceeds the import limit.") }
            if (response.status == 429 || (500...599).contains(response.status)), attempt < 2 {
                var requested = Double(response.headers["retry-after"] ?? "")
                if requested == nil, let header = response.headers["retry-after"] {
                    let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
                    formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
                    requested = formatter.date(from: header)?.timeIntervalSince(clock())
                }
                if let requested, requested > 30 { return response }
                let delay = max(1, requested ?? pow(2, Double(attempt)))
                try await sleep(delay)
                continue
            }
            return response
        }
        throw HubError.message("Garmin could not complete the request.")
    }
}
