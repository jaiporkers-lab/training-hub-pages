import SwiftUI
import TrainingHubCore

struct WalkthroughView: View {
    @ObservedObject var model: HubModel
    let reason: WelcomeReason?
    let finish: (String?) -> Void
    @State private var setupStep = false
    @State private var showKeySetup = false
    @AppStorage("map.showStreetBasemap") private var streets = true
    @AppStorage("appearance.mode") private var appearance = HubAppearance.system
    private var title: String {
        if setupStep { return "Bring in your recordings" }
        switch reason {
        case .returning: return "Welcome back to GarHub"
        case .updated: return "GarHub is updated"
        default: return "Welcome to GarHub"
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                HubBrandMark().frame(width: 34, height: 34)
                HubEyebrow("Welcome & setup", color: HubTheme.accent)
                Spacer()
                Text(setupStep ? "2 / 2" : "1 / 2").font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
            Text(title).hubHeading(size: 30)
            Text(setupStep ? "Import files or sync when ready. Then take a guided tour inside the app itself." : "Connect Garmin, choose your appearance and map preference, or continue with FIT files. Setup is optional and can be changed in Settings.")
                .font(.callout).foregroundStyle(HubTheme.muted).fixedSize(horizontal: false, vertical: true)
            ScrollView { if setupStep { setup } else { welcome } }.frame(height: 350)
            HStack {
                Button("Skip setup & tour") { finish(nil) }.buttonStyle(.link)
                Spacer()
                if setupStep { Button("Back") { setupStep = false } }
                Button(setupStep ? "Start live app tour" : "Continue") {
                    if setupStep { finish("Live tour") } else { setupStep = true }
                }.buttonStyle(HubPillStyle(selected: true)).keyboardShortcut(.defaultAction)
            }
            if !setupStep {
                Button("Take the app tour now") { finish("Live tour") }.buttonStyle(.link).font(.caption)
            }
        }.padding(26).frame(width: 650).foregroundStyle(HubTheme.ink).background(HubTheme.background)
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                Label("Connect Garmin", systemImage: "key").font(.headline)
                if model.keyAvailable && !showKeySetup {
                    Text(model.connectionStatus).font(.callout).foregroundStyle(HubTheme.muted)
                    Button("Use a different key…") { showKeySetup = true }.buttonStyle(.link)
                } else {
                    GarminConnectionSetup(model: model, showsInstructions: true)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).hubPanel(padding: 12)
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Apple Maps street basemap", isOn: $streets).toggleStyle(.switch)
                Text("The heatmap is drawn locally. Apple Maps can receive the area you view when streets are on. Switch this off for an offline map.")
                    .foregroundStyle(HubTheme.muted)
                Link("Apple Maps privacy", destination: URL(string: "https://www.apple.com/legal/privacy/data/en/apple-maps/")!)
            }.font(.callout).frame(maxWidth: .infinity, alignment: .leading).hubPanel(padding: 12)
            Picker("Appearance", selection: $appearance) {
                ForEach(HubAppearance.allCases, id: \.self) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented).hubPanel(padding: 12)
        }
    }

    private var setup: some View {
        let working = model.busy || model.syncing || model.healthSyncing
        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 7) {
                Text("Import files").font(.headline)
                Text("Choose one or more original FIT files. If you already have a backup, restore it in Settings → Library.")
                    .font(.callout).foregroundStyle(HubTheme.muted)
                Button("Import FIT…", action: model.chooseFITFiles).disabled(working || model.store == nil)
                if model.busy { ProgressView("Importing into your library…").controlSize(.small) }
                else if !model.groups.isEmpty {
                    let count = model.groups.count
                    Text(count == 1 ? "1 recording in your library" : "\(count.formatted()) recordings in your library")
                        .font(.caption).foregroundStyle(HubTheme.muted)
                }
                if let error = model.error {
                    Text(error).font(.caption).foregroundStyle(.secondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).hubPanel(padding: 12)
            VStack(alignment: .leading, spacing: 8) {
                Text("Garmin sync").font(.headline)
                if model.keyAvailable {
                    Text(model.connectionStatus).font(.callout).foregroundStyle(HubTheme.muted)
                    HStack {
                        Button("Test connection") { model.testConnection() }
                        Button("Sync recent activities") { model.beginSync(history: false) }
                        Button("Import all history") { model.beginSync(history: true, allHistory: true) }
                    }.disabled(working || model.testingConnection || model.store == nil)
                    if model.syncing {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text(model.syncProgress.message).font(.caption)
                            Button("Cancel") { model.cancelSync() }
                        }
                    } else {
                        Text("Import all history runs in resumable batches. You can keep exploring while it works.")
                            .font(.caption).foregroundStyle(HubTheme.muted)
                        if !model.syncProgress.message.isEmpty { Text(model.syncProgress.message).font(.caption) }
                    }
                } else {
                    GarminConnectionSetup(model: model)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).hubPanel(padding: 12)
        }
    }

}
