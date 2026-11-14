import SwiftUI
import AppKit
import TrainingHubCore

@main
struct TrainingHubApp: App {
    @StateObject private var model = HubModel()
    @AppStorage("appearance.mode") private var appearance = HubAppearance.system
    var body: some Scene {
        WindowGroup {
            HubView(model: model)
                .frame(minWidth: 1_040, minHeight: 680)
                .preferredColorScheme(appearance.scheme)
                .task { await model.start() }
        }
        .defaultSize(width: 1_240, height: 800)
        Settings {
            HubSettings(model: model).frame(width: 650, height: 590)
                .preferredColorScheme(appearance.scheme)
        }
    }
}

@MainActor
final class HubModel: ObservableObject {
    @Published var activities: [Activity] = []
    @Published var selectedID: String?
    @Published var busy = false
    @Published var error: String?
    @Published var status = "Local storage · No AI calls"
    @Published var keyAvailable = false
    @Published var connectionStatus = "Add a Garmin Personal API key to connect."
    @Published var testingConnection = false
    @Published var syncing = false
    @Published var healthSyncing = false
    @Published var health = HealthCache()
    @Published var healthStatus = "Sync health to load daily measurements."
    private var healthTask: Task<Void, Never>?
    @Published var syncProgress = SyncProgress()
    @Published var lastSync: Date?
    @Published var lastBackup: URL?
    @Published var syncIssues: [SyncIssue] = []
    private let syncService = GarminSync()
    private var syncTask: Task<Void, Never>?
    private var timerTask: Task<Void, Never>?
    var autoSync: Bool {
        get { UserDefaults.standard.bool(forKey: "garmin.autoSync") }
        set { UserDefaults.standard.set(newValue, forKey: "garmin.autoSync"); objectWillChange.send() }
    }
    private(set) var store: ActivityStore?
    private var started = false
    @Published private(set) var groups: [ActivityGroup] = []
    private(set) var selections: [Activity] = []
    var selectedGroup: ActivityGroup? { groups.first { $0.id == selectedID || $0.sessions.contains { $0.id == selectedID } } }

    func start() async {
        guard !started else { return }
        started = true
        do {
            let override = ProcessInfo.processInfo.environment["TRAINING_HUB_DATA_DIR"]
            let root = override.map { URL(fileURLWithPath: $0) } ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("GarminTrainingHub")
            store = try ActivityStore(root: root)
            do {
                if let recovery = try await store?.removeDemoActivities(preferences: preferencesData()) {
                    lastBackup = recovery
                    status = "Demo activities removed · Recovery backup saved"
                }
            } catch { self.error = error.localizedDescription }
            try await reload()
            do { keyAvailable = try GarminKeychain.hasKey() }
            catch { connectionStatus = error.localizedDescription }
            if keyAvailable { connectionStatus = "Key stored in Keychain. Test the connection or sync when ready." }
            lastSync = UserDefaults.standard.object(forKey: "garmin.lastSync") as? Date
            timerTask = Task { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(900)) } catch { return }
                    guard let self else { return }
                    if self.autoSync && self.keyAvailable && !self.busy && !self.syncing { self.beginSync(history: false) }
                }
            }
        } catch { self.error = error.localizedDescription }
    }

    func reload() async throws {
        guard let store else { return }
        let loaded = try await store.activities()
        let cachedHealth = try await store.healthCache()
        activities = loaded
        groups = ActivityGroup.grouping(loaded)
        selections = groups.flatMap { $0.isMultisport ? [$0.summary] + $0.sessions : $0.sessions }
        health = cachedHealth
        if !selections.contains(where: { $0.id == selectedID }) { selectedID = groups.first?.id }
    }

    func chooseFITFiles() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.resolvesAliases = false
        panel.prompt = "Import"
        panel.delegate = FITFilePicker.shared
        panel.begin { response in
            guard response == .OK else { return }
            Task { await self.importURLs(panel.urls) }
        }
    }

    private func importURLs(_ urls: [URL]) async {
        guard let store, !busy, !syncing, !healthSyncing else { return }
        busy = true
        defer { busy = false }
        var count = 0
        var failures: [String] = []
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            do { count += try await store.importFile(url) }
            catch { failures.append("\(url.lastPathComponent): \(error.localizedDescription)") }
            if scoped { url.stopAccessingSecurityScopedResource() }
        }
        do { try await reload() } catch { failures.append(error.localizedDescription) }
        status = "Imported \(count) session(s) · Exact duplicate files skipped"
        if !failures.isEmpty { error = failures.joined(separator: "\n") }
    }

    func saveKey(_ key: String) {
        guard !testingConnection, !syncing, !healthSyncing else { return }
        testingConnection = true
        connectionStatus = "Testing Garmin access…"
        Task {
            defer { testingConnection = false }
            do {
                try await syncService.client.verify(apiKey: key)
                try GarminKeychain.save(key)
                keyAvailable = true
                lastSync = nil; UserDefaults.standard.removeObject(forKey: "garmin.lastSync")
                connectionStatus = "Connected to Garmin. Key saved in Keychain and activity access verified."
            } catch {
                await syncService.client.disconnect()
                connectionStatus = "Connection not saved: \(error.localizedDescription)"
            }
        }
    }
    func testConnection() {
        guard !testingConnection, !syncing, !healthSyncing else { return }
        testingConnection = true
        Task {
            defer { testingConnection = false }
            do {
                let key = try GarminKeychain.read()
                try await syncService.client.verify(apiKey: key)
                connectionStatus = "Connected to Garmin. Activity access verified."
            } catch { connectionStatus = "Connection not verified: \(error.localizedDescription)" }
        }
    }
    func disconnectGarmin() {
        syncTask?.cancel(); healthTask?.cancel()
        autoSync = false
        do {
            try GarminKeychain.remove()
            keyAvailable = false
            connectionStatus = "Disconnected. Imported activities remain in your library."
            Task { await syncService.client.disconnect() }
        } catch { self.error = error.localizedDescription }
    }
    func beginSync(history: Bool, restart: Bool = false, allHistory: Bool = false) {
        guard let store, keyAvailable, !busy, !syncing, !testingConnection, !healthSyncing else { return }
        syncing = true
        syncProgress = SyncProgress(); syncProgress.message = "Preparing local safety backup…"
        syncTask = Task {
            defer { syncing = false; syncTask = nil }
            var scope: String?
            do {
                let key = try GarminKeychain.read()
                scope = "garmin." + FITImporter.hash(Data(key.utf8))
                if let backup = try await store.ensureFirstSyncBackup(preferences: preferencesData()) { lastBackup = backup }
                let update: @Sendable (SyncProgress) async -> Void = { progress in
                    await MainActor.run { self.syncProgress = progress }
                }
                let result: SyncProgress
                if allHistory { result = try await syncService.runAllHistory(store: store, apiKey: key, progress: update) }
                else { result = try await syncService.run(store: store, apiKey: key, history: history, restartHistory: restart, progress: update) }
                try await reload()
                status = result.message
                if result.failed == 0 && result.completed {
                    lastSync = Date(); UserDefaults.standard.set(lastSync, forKey: "garmin.lastSync")
                }
            } catch is CancellationError {
                syncProgress.message = "Sync cancelled. Finished imports are saved; you can resume later."
                try? await reload()
            } catch {
                syncProgress.message = "Sync paused: \(error.localizedDescription)"
                try? await reload()
            }
            if let scope { syncIssues = (try? await store.syncIssues(scope: scope)) ?? [] }
        }
    }
    func cancelSync() { syncTask?.cancel(); healthTask?.cancel() }

    func syncHealth(days: Int) {
        guard let store, keyAvailable, !busy, !syncing, !healthSyncing, !testingConnection, [7, 14, 30].contains(days) else { return }
        healthSyncing = true
        healthStatus = "Preparing health sync…"
        healthTask = Task {
            defer { healthSyncing = false; healthTask = nil }
            do {
                let key = try GarminKeychain.read()
                let calendar = Calendar.current
                let today = calendar.startOfDay(for: Date())
                let from = calendar.date(byAdding: .day, value: -2 * days, to: today)!
                let end = calendar.date(byAdding: .day, value: -1, to: today)!
                let formatter = HealthAnalysis.formatter()
                var failures: [String] = []
                for source in HealthSource.allCases {
                    var cursor = from
                    while cursor <= end {
                        try Task.checkCancellation()
                        let last = min(end, calendar.date(byAdding: .day, value: 30, to: cursor)!)
                        let fromKey = formatter.string(from: cursor), toKey = formatter.string(from: last)
                        healthStatus = "Loading \(source.title) · \(fromKey) – \(toKey)…"
                        do {
                            let records = try await syncService.client.health(apiKey: key, source: source, from: fromKey, to: toKey)
                            try Task.checkCancellation()
                            try await store.saveHealth(records, source: source, from: fromKey, to: toKey)
                            health = try await store.healthCache()
                        } catch {
                            if Task.isCancelled { throw CancellationError() }
                            if error is URLError { throw error }
                            if case GarminError.http(let code) = error, [401, 403, 429].contains(code) || code >= 500 { throw error }
                            failures.append("\(source.title): \(error.localizedDescription)")
                            break
                        }
                        cursor = calendar.date(byAdding: .day, value: 1, to: last)!
                    }
                }
                healthStatus = failures.isEmpty ? "Health sync complete. Daily measurements saved locally." : "Some health sources were unavailable. " + failures.joined(separator: " · ")
            } catch is CancellationError { healthStatus = "Health sync cancelled. Completed date batches are saved." }
            catch { healthStatus = "Health sync paused: \(error.localizedDescription)" }
        }
    }

    func createBackup() {
        guard let store, !busy, !syncing, !healthSyncing else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                let backup = try await store.createBackup(preferences: preferencesData())
                lastBackup = backup
                status = "Library backup created and verified."
                NSWorkspace.shared.activateFileViewerSelecting([backup])
            } catch { self.error = error.localizedDescription }
        }
    }
    func restoreBackup(_ folder: URL) {
        guard let store, !busy, !syncing, !healthSyncing else { return }
        busy = true
        Task {
            defer { busy = false }
            let scoped = folder.startAccessingSecurityScopedResource()
            defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
            do {
                let result = try await store.restoreBackup(folder, currentPreferences: preferencesData())
                if let preferences = result.preferences { try applyPreferences(preferences) }
                lastBackup = result.recoveryBackup
                syncIssues = []; lastSync = nil; UserDefaults.standard.removeObject(forKey: "garmin.lastSync")
                try await reload()
                status = "Library restored. A recovery backup of the previous library was saved."
            } catch { self.error = error.localizedDescription }
        }
    }
    func rename(fileHash: String, title: String) {
        guard let store, !busy else { return }
        Task {
            do { try await store.renameActivity(fileHash: fileHash, title: title); try await reload() }
            catch { self.error = error.localizedDescription }
        }
    }
    private func preferencesData() throws -> Data {
        let values = UserDefaults.standard.dictionaryRepresentation().filter { key, _ in
            ["feed.", "dashboard.", "zones.", "library.", "coach.", "calendar."].contains { key.hasPrefix($0) }
        }
        return try JSONSerialization.data(withJSONObject: values, options: [.sortedKeys])
    }
    private func applyPreferences(_ data: Data) throws {
        guard let values = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw HubError.message("Backup preferences could not be read.") }
        for key in UserDefaults.standard.dictionaryRepresentation().keys where ["feed.", "dashboard.", "zones.", "library.", "coach.", "calendar."].contains(where: { key.hasPrefix($0) }) {
            UserDefaults.standard.removeObject(forKey: key)
        }
        for (key, value) in values where ["feed.", "dashboard.", "zones.", "library.", "coach.", "calendar."].contains(where: { key.hasPrefix($0) }) {
            if value is String || value is NSNumber { UserDefaults.standard.set(value, forKey: key) }
        }
    }
}

@MainActor
private final class FITFilePicker: NSObject, NSOpenSavePanelDelegate {
    static let shared = FITFilePicker()

    func panel(_ sender: Any, shouldEnable url: URL) -> Bool {
        url.pathExtension.lowercased() == "fit" || (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }
}
