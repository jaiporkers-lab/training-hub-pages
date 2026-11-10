import Foundation
import CSQLite

public struct SyncProgress: Sendable {
    public init() {}
    public var message = "Ready"
    public var scanned = 0
    public var imported = 0
    public var duplicates = 0
    public var failed = 0
    public var hasMoreHistory = false
    public var completed = false
}

public struct SyncIssue: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let message: String
}

extension ActivityStore {
    func pendingGarminCount(scope: String) throws -> Int {
        let statement = try prepare("SELECT COUNT(*) FROM garmin_pending WHERE scope = ?")
        defer { sqlite3_finalize(statement) }
        try bind([.text(scope)], to: statement)
        guard sqlite3_step(statement) == SQLITE_ROW else { throw databaseError() }
        return Int(sqlite3_column_int64(statement, 0))
    }
    public func syncIssues(scope: String) throws -> [SyncIssue] {
        let statement = try prepare("SELECT activity_id, name, error FROM garmin_pending WHERE scope = ? ORDER BY activity_id LIMIT 20")
        defer { sqlite3_finalize(statement) }
        try bind([.text(scope)], to: statement)
        var result: [SyncIssue] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { return result }
            guard status == SQLITE_ROW, let id = sqlite3_column_text(statement, 0), let name = sqlite3_column_text(statement, 1), let message = sqlite3_column_text(statement, 2) else { throw databaseError() }
            result.append(SyncIssue(id: String(cString: id), name: String(cString: name), message: String(cString: message)))
        }
    }
    public func ensureFirstSyncBackup(preferences: Data? = nil) throws -> URL? {
        guard try syncValue("library.firstSyncBackup") == nil, try !activities().isEmpty else { return nil }
        let backup = try createBackup(preferences: preferences)
        try setSyncValue("library.firstSyncBackup", backup.lastPathComponent)
        return backup
    }
    func hasGarminActivity(_ id: String) throws -> Bool {
        let statement = try prepare("SELECT 1 FROM garmin_sources WHERE activity_id = ?")
        defer { sqlite3_finalize(statement) }
        try bind([.text(id)], to: statement)
        let status = sqlite3_step(statement)
        guard status == SQLITE_ROW || status == SQLITE_DONE else { throw databaseError() }
        return status == SQLITE_ROW
    }
    func linkGarminActivity(_ remote: GarminActivity, fileHash: String) throws {
        try Self.execute(db, "BEGIN IMMEDIATE")
        do {
            try run("INSERT OR REPLACE INTO garmin_sources VALUES (?, ?)", [.text(remote.id), .text(fileHash)])
            let title = remote.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty { try run("INSERT OR IGNORE INTO activity_titles VALUES (?, ?)", [.text(fileHash), .text(title)]) }
            try run("DELETE FROM garmin_pending WHERE activity_id = ?", [.text(remote.id)])
            try Self.execute(db, "COMMIT")
        } catch { try? Self.execute(db, "ROLLBACK"); throw error }
    }
    func pendingGarminActivities(scope: String) throws -> [GarminActivity] {
        let statement = try prepare("SELECT activity_id, name FROM garmin_pending WHERE scope = ? ORDER BY activity_id LIMIT 50")
        defer { sqlite3_finalize(statement) }
        try bind([.text(scope)], to: statement)
        var result: [GarminActivity] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { return result }
            guard status == SQLITE_ROW, let id = sqlite3_column_text(statement, 0), let name = sqlite3_column_text(statement, 1) else { throw databaseError() }
            result.append(GarminActivity(id: String(cString: id), name: String(cString: name)))
        }
    }
    func markGarminFailure(_ activity: GarminActivity, scope: String, message: String) throws {
        try run("INSERT INTO garmin_pending VALUES (?, ?, ?, ?) ON CONFLICT(scope, activity_id) DO UPDATE SET name=excluded.name, error=excluded.error",
                [.text(scope), .text(activity.id), .text(activity.name), .text(String(message.prefix(500)))])
    }
    public func syncValue(_ key: String) throws -> String? {
        let statement = try prepare("SELECT value FROM sync_state WHERE key = ?")
        defer { sqlite3_finalize(statement) }
        try bind([.text(key)], to: statement)
        let status = sqlite3_step(statement)
        if status == SQLITE_DONE { return nil }
        guard status == SQLITE_ROW, let text = sqlite3_column_text(statement, 0) else { throw databaseError() }
        return String(cString: text)
    }
    func setSyncValue(_ key: String, _ value: String) throws {
        try run("INSERT INTO sync_state VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value=excluded.value", [.text(key), .text(value)])
    }
}

public actor GarminSync {
    public let client: GarminClient
    private var running = false
    public init(client: GarminClient = GarminClient()) { self.client = client }

    public func run(store: ActivityStore, apiKey: String, history: Bool, restartHistory: Bool = false,
                    maxPages: Int = 10, pageSize: Int = 50,
                    progress: @escaping @Sendable (SyncProgress) async -> Void) async throws -> SyncProgress {
        guard !running else { throw HubError.message("A Garmin sync is already running.") }
        running = true
        defer { running = false }
        let scope = "garmin." + FITImporter.hash(Data(apiKey.utf8))
        var state = SyncProgress()
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"; formatter.locale = Locale(identifier: "en_US_POSIX")
        let now = Date()
        let last = try await store.syncValue(scope + ".lastSuccess").flatMap(Double.init).map { Date(timeIntervalSince1970: $0) }
        let from = last.map { Calendar.current.date(byAdding: .day, value: -2, to: $0)! } ?? Calendar.current.date(byAdding: .day, value: -30, to: now)!
        if history && restartHistory {
            try await store.setSyncValue(scope + ".historyOffset", "0")
            try await store.setSyncValue(scope + ".historyComplete", "false")
        }
        let saved = history && !restartHistory ? Int(try await store.syncValue(scope + ".historyOffset") ?? "0") ?? 0 : 0
        var offset = max(0, saved - (saved > 0 ? pageSize : 0))
        var endDate = formatter.string(from: now)
        if history {
            if saved == 0 { try await store.setSyncValue(scope + ".historyEnd", endDate) }
            else { endDate = try await store.syncValue(scope + ".historyEnd") ?? endDate }
        }
        var visited = Set<String>()
        let pending = try await store.pendingGarminActivities(scope: scope)
        for remote in pending {
            try Task.checkCancellation()
            visited.insert(remote.id)
            await progress(state)
            try await process(remote, store: store, apiKey: apiKey, scope: scope, state: &state)
        }
        var complete = false
        for _ in 0..<maxPages {
            try Task.checkCancellation()
            state.message = history ? "Reading history from activity \(offset + 1)…" : "Checking recent activities…"
            await progress(state)
            let page = try await client.activities(apiKey: apiKey, offset: offset, limit: pageSize,
                startDate: history ? nil : formatter.string(from: from), endDate: endDate)
            for remote in page {
                try Task.checkCancellation()
                guard visited.insert(remote.id).inserted, remote.parentID == nil else { continue }
                state.message = "Importing \(remote.name)…"
                await progress(state)
                try await process(remote, store: store, apiKey: apiKey, scope: scope, state: &state)
            }
            offset += page.count
            if history { try await store.setSyncValue(scope + ".historyOffset", String(offset)) }
            if page.count < pageSize { complete = true; break }
        }
        try Task.checkCancellation()
        state.hasMoreHistory = history && !complete
        state.completed = complete
        state.failed = max(state.failed, try await store.pendingGarminCount(scope: scope))
        if complete && state.failed == 0 { try await store.setSyncValue(scope + ".lastSuccess", String(now.timeIntervalSince1970)) }
        if history && complete { try await store.setSyncValue(scope + ".historyComplete", "true") }
        state.message = state.hasMoreHistory ? "History paused at \(offset) activities. Continue history to load older recordings." :
            "Sync finished: \(state.imported) imported, \(state.duplicates) already present, \(state.failed) need retry."
        if !history && !complete { state.message += " Use history import to load additional older activities." }
        await progress(state)
        return state
    }

    public func runAllHistory(store: ActivityStore, apiKey: String, maxPages: Int = 10, pageSize: Int = 50,
                              progress: @escaping @Sendable (SyncProgress) async -> Void) async throws -> SyncProgress {
        var total = SyncProgress()
        var batch = 0
        let scope = "garmin." + FITImporter.hash(Data(apiKey.utf8))
        repeat {
            try Task.checkCancellation()
            batch += 1
            let prior = total
            let batchNumber = batch
            let before = try await store.syncValue(scope + ".historyOffset") ?? "0"
            let result = try await run(store: store, apiKey: apiKey, history: true, maxPages: maxPages, pageSize: pageSize) { update in
                var combined = update
                combined.scanned += prior.scanned; combined.imported += prior.imported; combined.duplicates += prior.duplicates
                combined.message = "Batch \(batchNumber) · \(update.message)"
                await progress(combined)
            }
            total = result
            total.scanned += prior.scanned; total.imported += prior.imported; total.duplicates += prior.duplicates
            if !result.hasMoreHistory {
                total.message = "History import complete: \(total.imported) imported, \(total.duplicates) already present, \(total.failed) need retry."
                await progress(total)
                return total
            }
            let after = try await store.syncValue(scope + ".historyOffset") ?? "0"
            guard (Int(after) ?? 0) > (Int(before) ?? 0) else {
                throw HubError.message("History paused because Garmin pagination did not advance. Your completed imports are saved.")
            }
        } while true
    }

    private func process(_ remote: GarminActivity, store: ActivityStore, apiKey: String, scope: String, state: inout SyncProgress) async throws {
        state.scanned += 1
        do {
            if try await store.hasGarminActivity(remote.id) { state.duplicates += 1; return }
            let download = try await client.download(apiKey: apiKey, activityID: remote.id)
            try Task.checkCancellation()
            let data: Data
            if download.count >= 12, download.subdata(in: 8..<12) == Data(".FIT".utf8) { data = download }
            else {
                let entries = try FITZip.read(download)
                guard entries.count == 1 else { throw HubError.message("This original contains multiple FIT files and needs manual review.") }
                data = entries[0].data
            }
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("TrainingHubSync-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            defer { try? FileManager.default.removeItem(at: folder) }
            let file = folder.appendingPathComponent("Garmin-\(remote.id).fit")
            try data.write(to: file, options: .atomic)
            let imported = try await store.importFile(file)
            try await store.linkGarminActivity(remote, fileHash: FITImporter.hash(data))
            if imported > 0 { state.imported += 1 } else { state.duplicates += 1 }
        } catch is CancellationError { throw CancellationError() }
        catch {
            if Task.isCancelled { throw CancellationError() }
            if error is URLError { throw error }
            if case GarminError.http(let status) = error, [401, 403, 429].contains(status) || status >= 500 { throw error }
            state.failed += 1
            try await store.markGarminFailure(remote, scope: scope, message: error.localizedDescription)
        }
    }
}
