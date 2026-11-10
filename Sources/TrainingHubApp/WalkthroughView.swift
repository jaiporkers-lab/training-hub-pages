import SwiftUI
import TrainingHubCore

struct WalkthroughView: View {
    @ObservedObject var model: HubModel
    let reason: WelcomeReason?
    let finish: (String?) -> Void
    @State private var step = Step.welcome
    @State private var showKeySetup = false
    @AppStorage("map.showStreetBasemap") private var streets = true
    @AppStorage("appearance.mode") private var appearance = HubAppearance.system

    private enum Step: Int, CaseIterable {
        case welcome, setup, library, inspect, analyse, trends, explore, whatsNew

        var title: String {
            switch self {
            case .welcome: "Welcome to Training Hub"
            case .setup: "Bring in your activities"
            case .library: "Make it your training library"
            case .inspect: "Get closer to a recording"
            case .analyse: "Find the detail you need"
            case .trends: "See the bigger picture"
            case .explore: "Compare your efforts and routes"
            case .whatsNew: "What’s new"
            }
        }

        var subtitle: String {
            switch self {
            case .welcome: "Connect Garmin here or continue to import FIT files and take the tour."
            case .setup: "Add FIT files, connect Garmin, or come back to setup later."
            case .library: "Make Home and the activity feed work the way you train."
            case .inspect: "Open a recording from the feed or use the latest recording on Home."
            case .analyse: "Use the analysis tabs above the chart to switch views."
            case .trends: "Zoom out from individual sessions to weeks, recovery and your next training block."
            case .explore: "Put two efforts side by side or find the routes you use most."
            case .whatsNew: "See what changed in this update, then jump straight into Map."
            }
        }
    }

    private var title: String {
        guard step == .welcome else { return step.title }
        switch reason {
        case .returning: return "Welcome back"
        case .updated: return "Training Hub is updated"
        default: return step.title
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 9) {
                HubBrandMark().frame(width: 30, height: 30)
                HubEyebrow("Training Hub walkthrough", color: HubTheme.accent)
                Spacer()
                Text("Step \(step.rawValue + 1) of \(Step.allCases.count)")
                    .font(.caption.monospacedDigit()).foregroundStyle(HubTheme.muted)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(title).hubHeading(size: 31)
                Text(step.subtitle).font(.callout).foregroundStyle(HubTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .contain)
            ProgressView(value: Double(step.rawValue + 1), total: Double(Step.allCases.count))
                .tint(HubTheme.accent).accessibilityLabel("Walkthrough progress")
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    switch step {
                    case .welcome: welcome
                    case .setup: setup
                    case .library:
                        feature("Home", "house", "Open the latest recording or set a weekly goal. Use Customise Home to choose cards, and the logo or ⌘1 to return Home.")
                        feature("Activity feed", "magnifyingglass", "Search by name or sport, filter by date, and sort the results. Save a filter in Views or switch to the compact feed.")
                        feature("Dashboard", "slider.horizontal.3", "Open Dashboard in Activities to see totals for the current filters and choose which totals to show.")
                    case .inspect:
                        feature("Whole race or one leg", "figure.mixed.cardio", "Expand a multisport recording in the feed. Select a leg or use Entire activity to return to the race.")
                        feature("Inspect the chart", "cursorarrow", "Hover to read the recorded value and race leg. Click or drag to pin a reading and use the range sliders to focus on an interval.")
                        feature("Chart controls", "waveform.path", "Choose a metric, align by time or distance, and adjust smoothing. Add a second recording for an overlay.")
                    case .analyse:
                        feature("Laps & splits and Zones", "timer", "Select a lap to focus its chart interval, or set your heart-rate and power thresholds in Zones.")
                        feature("All stats and Pool lengths", "list.bullet.rectangle", "Find recorded FIT fields. Pool recordings can show individual lengths, rests, strokes and SWOLF.")
                        feature("Export and back up", "square.and.arrow.up", "Export sensor or lap CSVs from an activity. Create or restore a verified backup in Settings → Library.")
                    case .trends:
                        feature("Training trends", "chart.bar", "Compare weekly time and distance, or filter the view by sport.")
                        feature("Health & recovery", "heart.text.square", "Use Sync health to load supported Garmin measurements, then compare sleep, HRV and other metrics across periods.")
                        feature("Prompt builder", "text.document", "Build a coaching brief locally and review it before copying. Health averages are optional.")
                    case .explore:
                        feature("Compare", "chart.xyaxis.line", "Overlay two activities by time or distance. Use one cursor for both traces, compare matched race legs, or switch to elapsed and timer bars.")
                        feature("Personal heatmap", "map", "Pan and zoom to see where your routes overlap. Filter by period, sport or recording, or open Map straight from an activity.")
                    case .whatsNew:
                        feature("Garmin setup", "key", "Create a Garmin Personal API key using the link on the welcome screen, then paste it there to verify the connection.")
                        newFeature("Map", "map", "Hover over the heatmap to count nearby outdoor recordings. Click to pin the spot and open any matching activity.")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }.frame(height: 352)
                .id(step)
            HStack(spacing: 10) {
                if step != .whatsNew {
                    Button("Skip walkthrough") { finish(nil) }
                        .buttonStyle(.link)
                }
                Spacer()
                Button("Back") { move(-1) }.disabled(step == .welcome)
                Button(step == .whatsNew ? "Done" : step == .welcome ? "Get started" : "Next") {
                    if step == .whatsNew { finish(nil) } else { move(1) }
                }
                .buttonStyle(HubPillStyle(selected: true))
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(26)
        .frame(width: 650)
        .foregroundStyle(HubTheme.ink)
        .background(HubTheme.paper)
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
                ForEach(HubAppearance.allCases, id: \.self) { Text($0.rawValue).tag($0) }
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

    private func feature(_ title: String, _ symbol: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(HubTheme.accent)
                .frame(width: 36, height: 36)
                .background(HubTheme.accentWash, in: RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(HubTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .hubPanel(padding: 12)
        .accessibilityElement(children: .combine)
    }

    private func newFeature(_ destination: String, _ symbol: String, _ detail: String) -> some View {
        Button {
            finish(destination)
        } label: {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(HubTheme.lime)
                    .frame(width: 40, height: 40)
                    .background(HubTheme.boardRaised, in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(destination).font(.title3.bold())
                        Text("NEW").font(.caption2.bold()).tracking(0.6)
                            .foregroundStyle(HubTheme.forest)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(HubTheme.lime, in: Capsule())
                    }
                    Text(detail).font(.callout).foregroundStyle(HubTheme.boardMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "arrow.up.right").foregroundStyle(HubTheme.lime)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(HubTheme.boardText)
            .padding(15)
            .background(HubTheme.forest, in: RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open \(destination), new")
        .accessibilityHint(detail)
    }

    private func move(_ offset: Int) {
        if let next = Step(rawValue: step.rawValue + offset) { step = next }
    }
}
