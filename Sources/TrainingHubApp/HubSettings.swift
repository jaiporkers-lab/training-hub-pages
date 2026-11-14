import SwiftUI
import AppKit
import TrainingHubCore

struct HubSettings: View {
    @ObservedObject var model: HubModel
    @AppStorage("appearance.mode") private var appearance = HubAppearance.system
    @State private var restoreFolder: URL?
    @State private var restoreManifest: BackupManifest?
    @State private var confirmRestore = false
    var body: some View {
        TabView {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Label("Garmin connection", systemImage: "arrow.triangle.2.circlepath").font(.title2.bold())
                    GarminConnectionSetup(model: model)
                    Divider()
                    HStack {
                        Button("Sync recent activities") { model.beginSync(history: false) }
                        Button("Import all Garmin history") { model.beginSync(history: true, allHistory: true) }
                    }.disabled(!model.keyAvailable || model.busy || model.syncing || model.healthSyncing || model.testingConnection)
                    HStack {
                        Button("Rescan history") { model.beginSync(history: true, restart: true) }.disabled(!model.keyAvailable || model.busy || model.syncing || model.healthSyncing || model.testingConnection)
                        if model.syncing { Button("Cancel sync") { model.cancelSync() }; ProgressView().controlSize(.small) }
                    }
                    Toggle("Sync every 15 minutes while the app is open", isOn: Binding(get: { model.autoSync }, set: { model.autoSync = $0 }))
                        .disabled(!model.keyAvailable)
                    Text(model.syncProgress.message).font(.callout).textSelection(.enabled)
                    if model.syncProgress.scanned > 0 {
                        Text("Checked \(model.syncProgress.scanned) · Imported \(model.syncProgress.imported) · Already present \(model.syncProgress.duplicates) · Need retry \(model.syncProgress.failed)")
                            .font(.caption).monospacedDigit()
                    }
                    ForEach(model.syncIssues) { issue in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(issue.name).font(.caption.bold())
                            Text(issue.message).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if let lastSync = model.lastSync { Text("Last completed sync: \(lastSync.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary) }
                    Text("Recent sync starts with the last 30 days, then overlaps the last successful sync. Import all history continues automatically in batches of up to 500 listed activities. Keep the app open; cancel anytime and use the same button to resume. Failed activity imports are queued for retry. A verified library backup is made before the first sync.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Disconnect and remove stored key") { model.disconnectGarmin() }.disabled(!model.keyAvailable || model.testingConnection)
                }.padding(24)
            }.tabItem { Label("Garmin", systemImage: "arrow.triangle.2.circlepath") }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Label("Library backups", systemImage: "externaldrive").font(.title2.bold())
                    Text("Backups include a consistent database, original FIT files, activity names and display/zone preferences. Credentials and generated CSV exports are excluded.")
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("Create verified backup") { model.createBackup() }
                        Button("Choose backup to restore…") { chooseRestore() }
                        if model.busy { ProgressView().controlSize(.small) }
                    }.disabled(model.busy || model.syncing || model.healthSyncing || model.store == nil)
                    if let backup = model.lastBackup {
                        Text(backup.lastPathComponent).font(.caption).textSelection(.enabled)
                        Button("Show latest backup in Finder") { NSWorkspace.shared.activateFileViewerSelecting([backup]) }
                    }
                    Text("Backups are private local .thbackup folders in your library's Backups folder. Copy the entire folder to another disk for a separate backup. Restore validates checksums and database integrity, and creates a recovery backup before replacing the library.")
                        .font(.caption).foregroundStyle(.secondary)
                    Divider()
                    Text(model.status).font(.callout)
                    Text("Backup files contain your private activity data, including original GPS recordings. They are not encrypted by this prototype.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(24)
            }.tabItem { Label("Library", systemImage: "externaldrive") }
            VStack(alignment: .leading, spacing: 16) {
                HubEyebrow("Personal workspace", color: HubTheme.accent)
                Text("Appearance").hubHeading()
                Picker("Appearance", selection: $appearance) {
                    ForEach(HubAppearance.allCases, id: \.self) { option in
                        Text(option.title).tag(option)
                    }
                }.pickerStyle(.segmented).frame(maxWidth: 400)
                Text("Choose Light, Dark or Match Mac. Blue charts and the same controls are available in every mode.")
                    .foregroundStyle(HubTheme.muted)
                Spacer(minLength: 0)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(HubTheme.background)
            .tabItem { Label("Appearance", systemImage: "circle.lefthalf.filled") }
        }
        .padding(8)
        .confirmationDialog("Restore this backup?", isPresented: $confirmRestore, titleVisibility: .visible) {
            Button("Restore library", role: .destructive) { if let restoreFolder { model.restoreBackup(restoreFolder) } }
        } message: {
            Text("\(restoreManifest?.originals.count ?? 0) original files · \(restoreManifest?.activityCount ?? 0) sessions. A recovery backup of the current library will be created first.")
        }
    }
    private func chooseRestore() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
        panel.resolvesAliases = false; panel.prompt = "Inspect backup"
        panel.begin { response in
            guard response == .OK, let folder = panel.url else { return }
            Task {
                do {
                    let manifest = try await Task.detached { try ActivityStore.inspectBackup(folder) }.value
                    restoreFolder = folder; restoreManifest = manifest; confirmRestore = true
                } catch { model.error = error.localizedDescription }
            }
        }
    }
}

struct GarminConnectionSetup: View {
    @ObservedObject var model: HubModel
    var showsInstructions = false
    @State private var key = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsInstructions {
                VStack(alignment: .leading, spacing: 4) {
                    Link("1. Open Garmin Personal API settings", destination: Self.settingsURL)
                    Text("2. Sign in to Garmin Connect, create a Personal API key and copy it.")
                    Text("3. Paste the key below and select Save & test connection.")
                }.font(.callout).foregroundStyle(HubTheme.muted)
            } else {
                Text("Connect your own Garmin account using its Personal API. Your key is stored in macOS Keychain.")
                    .foregroundStyle(.secondary)
                Link("Open Garmin Personal API settings", destination: Self.settingsURL)
            }
            SecureField("Personal API key", text: $key, prompt: Text("Paste your Garmin key"))
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("Save & test connection") {
                    let entered = key
                    key = ""
                    model.saveKey(entered)
                }.disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if model.keyAvailable { Button("Test stored key") { model.testConnection() } }
                if model.testingConnection { ProgressView().controlSize(.small) }
            }.disabled(model.testingConnection || model.syncing || model.healthSyncing)
            Text(model.connectionStatus).font(.callout).textSelection(.enabled)
            if showsInstructions {
                Label("GarHub verifies your key with Garmin and saves it in macOS Keychain.", systemImage: "lock.shield")
                    .font(.caption).foregroundStyle(HubTheme.muted)
            }
        }
    }

    private static let settingsURL = URL(string: "https://connect.garmin.com/app/settings/personalApiToken")!
}
