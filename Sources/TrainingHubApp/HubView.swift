import SwiftUI
import AppKit
import TrainingHubCore

struct HubView: View {
    @ObservedObject var model: HubModel
    @State private var page = "Home"
    @State private var tourStep: AppTourStep?
    @State private var routeFocus = ""
    @State private var showingWalkthrough = false
    @State private var welcomeReason: WelcomeReason?
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("walkthrough.presentedRelease") private var walkthroughRelease = ""
    @AppStorage("walkthrough.lastUse") private var walkthroughLastUse = 0.0
    @AppStorage("walkthrough.visitedCompare") private var visitedCompare = false
    @AppStorage("walkthrough.visitedMap") private var visitedMap = false
    @State private var search = ""
    @State private var sport = "All sports"
    @AppStorage("feed.compact") private var compact = false
    @AppStorage("dashboard.distance") private var showDistance = true
    @AppStorage("dashboard.duration") private var showDuration = true
    @AppStorage("dashboard.count") private var showCount = true
    @AppStorage("dashboard.compact") private var compactDashboard = false
    @AppStorage("feed.days") private var days = 0
    @AppStorage("feed.sort") private var sort = "Newest first"
    @AppStorage("library.savedViews") private var savedViewsJSON = "[]"
    @State private var renameHash: String?
    @State private var renameText = ""
    @State private var showRename = false
    @State private var showingDashboard = false

    private var savedViews: [SavedLibraryView] { (try? JSONDecoder().decode([SavedLibraryView].self, from: Data(savedViewsJSON.utf8))) ?? [] }
    private var filteredGroups: [ActivityGroup] {
        model.groups.filter { $0.matches(search: search, sport: sport) && (days == 0 || $0.summary.start >= Date().addingTimeInterval(-Double(days) * 86_400)) }
            .sorted { lhs, rhs in
                switch sort {
                case "Oldest first": return lhs.summary.start < rhs.summary.start
                case "Longest distance": return (lhs.summary.distance ?? -1) > (rhs.summary.distance ?? -1)
                case "Longest time": return lhs.summary.elapsed > rhs.summary.elapsed
                default: return lhs.summary.start > rhs.summary.start
                }
            }
    }
    private func feed(_ groups: [ActivityGroup]) -> [FeedItem] { groups.map { group in
        FeedItem(activity: group.summary, title: group.summary.title,
                 detail: group.isMultisport ? "\(group.summary.displaySport) · \(group.sessions.count) legs" : group.summary.displaySport,
                 baseTitle: group.summary.title,
                 children: group.isMultisport ? group.sessions.map { FeedItem(activity: $0, title: group.legName($0), detail: $0.displaySport, baseTitle: group.summary.title, children: nil) } : nil)
    } }
    var body: some View {
        let visibleGroups = filteredGroups
        let filtered = visibleGroups.map(\.summary)
        let items = feed(visibleGroups)
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 12) {
                Button { page = "Home" } label: {
                    HStack(spacing: 10) {
                        HubBrandMark().frame(width: 34, height: 34)
                        VStack(alignment: .leading, spacing: 2) {
                            GarHubWordmark()
                            HubEyebrow("Personal training log")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("GarHub logo · Home")
                .help("Go Home")
                .padding(.top, 14)
                Button { page = "Home" } label: {
                    Label("Home", systemImage: "house").frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(HubPillStyle(selected: page == "Home"))
                .keyboardShortcut("1", modifiers: .command)
                .help("Home · ⌘1")
                HubEyebrow("Activity library")
                TextField("Search activities", text: $search)
                    .textFieldStyle(.roundedBorder)
                Picker("Sport", selection: $sport) {
                    Text("All sports").tag("All sports")
                    ForEach(Array(Set(model.selections.map(\.sport))).sorted(), id: \.self) { Text($0.capitalized).tag($0) }
                }.labelsHidden()
                HStack {
                    Picker("Date range", selection: $days) {
                        Text("All dates").tag(0); Text("Last 7 days").tag(7); Text("Last 30 days").tag(30); Text("Last 90 days").tag(90)
                    }.labelsHidden()
                    Menu {
                        ForEach(savedViews) { view in
                            Button(view.title) { search = view.search; sport = view.sport; days = view.days; sort = view.sort }
                        }
                        Divider()
                        Button("Save current view") { saveView() }
                        ForEach(savedViews) { view in
                            Button("Remove \(view.title)") { saveViews(savedViews.filter { $0.id != view.id }) }
                        }
                    } label: { Label("Views", systemImage: "line.3.horizontal.decrease.circle") }.fixedSize()
                }
                Picker("Sort", selection: $sort) {
                    ForEach(["Newest first", "Oldest first", "Longest distance", "Longest time"], id: \.self) { Text($0).tag($0) }
                }.labelsHidden()
                HStack {
                    Text("\(filtered.count) activities").foregroundStyle(.secondary)
                    Spacer()
                    Toggle(isOn: $compact) { Image(systemName: "list.bullet") }
                        .toggleStyle(.button).help("Compact activity feed")
                }.font(.caption)
                List(items, children: \.children, selection: $model.selectedID) { item in
                    let activity = item.activity
                    VStack(alignment: .leading, spacing: 5) {
                        Label {
                            Text(item.title).font(.callout.weight(.semibold)).lineLimit(2)
                        } icon: {
                            Image(systemName: sportSymbol(activity.sport))
                                .symbolRenderingMode(.monochrome)
                                .foregroundStyle(HubTheme.accent)
                                .frame(width: 15)
                        }
                        Text(item.detail).font(.caption).foregroundStyle(.secondary)
                        if !compact {
                            Text(activity.start, format: .dateTime.day().month(.abbreviated).year())
                                .font(.caption).foregroundStyle(.secondary)
                            Text("\(distance(activity.distance)) · \(duration(activity.timer ?? activity.elapsed))")
                                .font(.caption.weight(.medium)).monospacedDigit()
                        }
                    }.padding(.vertical, compact ? 2 : 7).tag(activity.id)
                    .contentShape(Rectangle())
                    .simultaneousGesture(TapGesture().onEnded {
                        model.selectedID = activity.id
                        page = "Activities"
                    })
                    .contextMenu {
                        Button("Rename activity…") { renameHash = activity.fileHash; renameText = item.baseTitle; showRename = true }
                    }
                }.listStyle(.sidebar)
                    .scrollContentBackground(.hidden)
                    .overlay {
                        if items.isEmpty && !model.activities.isEmpty {
                            VStack(spacing: 10) {
                                Image(systemName: "line.3.horizontal.decrease.circle").font(.title2).foregroundStyle(.secondary)
                                Text("No matching activities").font(.headline)
                                Button("Clear filters") { search = ""; sport = "All sports"; days = 0 }
                            }.padding()
                        }
                    }
                Text((Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String).map { "Version \($0) · Data stays on this Mac" } ?? "Data stays on this Mac")
                    .font(.caption2).foregroundStyle(.secondary)
                Link(destination: URL(string: "https://github.com/jaiporkers-lab/training-hub-pages/issues")!) {
                    Label("Report an issue", systemImage: "bubble.left.and.exclamationmark.bubble.right")
                }.font(.caption).buttonStyle(.link)
                    .help("Open GarHub’s GitHub issues page. No activity data is attached automatically.")
            }.padding(.horizontal, 14).padding(.bottom, 12)
            .background(HubTheme.sidebar)
            .navigationSplitViewColumnWidth(min: 260, ideal: 290)
        } detail: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    ScrollView(.horizontal) {
                        HStack(spacing: 5) {
                            workspaceButton("Home", page: "Home")
                            workspaceButton("Activities", page: "Activities")
                            workspaceButton("Training trends", page: "Trends")
                            workspaceButton("Calendar", page: "Calendar")
                            workspaceButton("Goals", page: "Goals")
                            workspaceButton("Recovery", page: "Recovery")
                            workspaceButton("Health", page: "Health")
                            workspaceButton("Compare", page: "Compare")
                            workspaceButton("Map", page: "Map")
                            workspaceButton("Prompt builder", page: "Coach")
                        }
                        .padding(.vertical, 2)
                    }
                    .scrollIndicators(.hidden)
                    if page == "Activities" {
                        Button { showingDashboard.toggle() } label: {
                            Label("Dashboard", systemImage: "slider.horizontal.3")
                        }
                        .fixedSize()
                        .popover(isPresented: $showingDashboard, arrowEdge: .bottom) {
                            libraryDashboard(filtered)
                        }
                    }
                }
                Rectangle().fill(HubTheme.line).frame(height: 1)
                if page == "Home" {
                    HomeView(model: model, navigate: { page = $0 }, openActivity: { model.selectedID = $0; page = "Activities" })
                } else if page == "Calendar" { TrainingCalendarView(groups: model.groups) { model.selectedID = $0; page = "Activities" } }
                else if page == "Goals" { TrainingProgressView(activities: model.activities, store: model.store) { model.selectedID = $0; page = "Activities" } }
                else if page == "Recovery" { RecoveryTrendsView(model: model) }
                else if page == "Health" { HealthMetricsView(model: model) }
                else if page == "Compare" { ActivityComparisonView(groups: model.groups, preferredID: model.selectedGroup?.id, store: model.store) { model.selectedID = $0; page = "Activities" } }
                else if page == "Map" {
                    if let store = model.store {
                        RouteExplorerView(groups: model.groups, store: store, initialID: routeFocus) {
                            model.selectedID = $0
                            page = "Activities"
                        }.id(routeFocus)
                    } else {
                        ProgressView("Opening the local library…").frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else if page == "Coach" { CoachView(activities: model.activities, health: model.health.days) }
                else if page == "Trends" {
                    TrainingTrendsView(activities: model.activities)
                } else {
                    if let activity = model.selections.first(where: { $0.id == model.selectedID }), let store = model.store {
                        ActivityDetail(activity: activity, all: model.selections, store: store, group: model.selectedGroup, groups: model.groups,
                                       selectActivity: { model.selectedID = $0 }, openRoute: {
                            routeFocus = model.selectedGroup?.id ?? activity.id
                            page = "Map"
                        }, guidedSection: tourStep.flatMap { tourNeedsRecording($0) ? nil : $0.section }).id(activity.id)
                    } else {
                        ContentUnavailableView {
                            Label(model.activities.isEmpty ? "Start with one activity" : visibleGroups.isEmpty ? "No matching activities" : "Choose an activity", systemImage: "chart.xyaxis.line")
                        } description: {
                            Text(model.activities.isEmpty ? "Import an original .fit file or connect Garmin to start your library." : visibleGroups.isEmpty ? "Try another search or clear the filters to return to your library." : "Select an activity from the feed to open its charts and recorded stats.")
                        } actions: {
                            if model.activities.isEmpty { Button("Import FIT…", action: model.chooseFITFiles).disabled(model.store == nil) }
                            else { Button("Clear filters") { search = ""; sport = "All sports"; days = 0; applyFilter() } }
                        }
                        Spacer()
                    }
                }
                Rectangle().fill(HubTheme.line).frame(height: 1)
                HStack {
                    if model.busy || model.syncing || model.healthSyncing { ProgressView().controlSize(.small) }
                    Text(model.healthSyncing ? model.healthStatus : model.syncing ? model.syncProgress.message : model.status).font(.caption).foregroundStyle(.secondary)
                    if model.syncing || model.healthSyncing { Button("Cancel") { model.cancelSync() }.controlSize(.small) }
                    Spacer()
                    Label("Local processing", systemImage: "lock.shield").font(.caption).foregroundStyle(.secondary)
                }
            }.padding(.horizontal, 24).padding(.vertical, 14)
                .background(HubTheme.background)
                .overlay(alignment: .bottomTrailing) {
                    if let tourStep {
                        GuidedAppTourCard(step: tourStep, missingRecording: tourNeedsRecording(tourStep), move: moveTour, finish: { self.tourStep = nil }, explore: showTourStep)
                            .frame(maxWidth: 650).padding(16).padding(.bottom, 28)
                    }
                }
        }
        .foregroundStyle(HubTheme.ink)
        .tint(HubTheme.accent)
        .onAppear { checkWelcome() }
        .onChange(of: scenePhase) { previous, current in
            if current == .active { checkWelcome() }
            else if previous == .active { walkthroughLastUse = Date().timeIntervalSince1970 }
        }
        .onChange(of: page) {
            if page == "Compare" { visitedCompare = true }
            if page == "Map" { visitedMap = true }
        }
        .onChange(of: search) { applyFilter() }
        .onChange(of: sport) { applyFilter() }
        .onChange(of: days) { applyFilter() }
        .onChange(of: model.selectedID) { oldValue, newValue in if oldValue != nil && newValue != nil { page = "Activities" } }
        .toolbar {
            Button(action: model.chooseFITFiles) { Label("Import FIT", systemImage: "square.and.arrow.down") }
                .disabled(model.busy || model.syncing || model.healthSyncing || model.store == nil)
            if model.keyAvailable {
                Button { model.beginSync(history: false) } label: { Label("Sync", systemImage: "arrow.triangle.2.circlepath") }
                    .disabled(model.busy || model.syncing || model.healthSyncing || model.testingConnection)
            } else {
                SettingsLink { Label("Connect Garmin", systemImage: "arrow.triangle.2.circlepath") }
            }
            Button("Import all history") { model.beginSync(history: true, allHistory: true) }
                .help("Import all Garmin history in resumable batches")
                .disabled(!model.keyAvailable || model.busy || model.syncing || model.healthSyncing || model.testingConnection)
            Button { welcomeReason = nil; showingWalkthrough = true } label: {
                Label("Feature walkthrough", systemImage: "questionmark.circle")
            }.help("Feature walkthrough")
            SettingsLink { Label("Settings", systemImage: "gearshape") }
        }
        .sheet(isPresented: $showingWalkthrough) {
            WalkthroughView(model: model, reason: welcomeReason) { destination in
                showingWalkthrough = false
                if destination == "Live tour" { showTourStep(.home) }
                else if let destination { openWorkspace(destination) }
            }
        }
        .alert("GarHub", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
        .sheet(isPresented: $showRename) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Rename activity").font(.title2.bold())
                TextField("Activity name", text: $renameText).textFieldStyle(.roundedBorder)
                HStack {
                    Button("Cancel") { showRename = false }
                    Spacer()
                    Button("Save") { if let renameHash { model.rename(fileHash: renameHash, title: renameText) }; showRename = false }
                        .keyboardShortcut(.defaultAction).disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }.padding(24).frame(width: 420)
        }
    }

    private func checkWelcome() {
        let now = Date()
        let release = [
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        ].compactMap { $0 }.joined(separator: "/")
        let reason = WelcomeReason.resolve(
            currentRelease: release.isEmpty ? "development" : release,
            previousRelease: walkthroughRelease.isEmpty ? nil : walkthroughRelease,
            hasUsedEarlierVersion: UserDefaults.standard.integer(forKey: "walkthrough.seenRevision") > 0,
            lastUse: walkthroughLastUse > 0 ? Date(timeIntervalSince1970: walkthroughLastUse) : nil,
            now: now
        )
        walkthroughLastUse = now.timeIntervalSince1970
        if let reason, !showingWalkthrough, tourStep == nil {
            walkthroughRelease = release.isEmpty ? "development" : release
            welcomeReason = reason
            showingWalkthrough = true
        }
    }
    private func libraryDashboard(_ activities: [Activity]) -> some View {
        let totalDistance = distance(activities.compactMap(\.distance).reduce(0, +))
        let totalTime = duration(activities.reduce(0) { $0 + ($1.timer ?? $1.elapsed) })
        return VStack(alignment: .leading, spacing: 14) {
            Text("Library totals").hubHeading(size: 20)
            Text("Complete activities matching the feed filters. Time uses the recorded timer when available.")
                .font(.caption).foregroundStyle(HubTheme.muted)
            if compactDashboard {
                HStack(spacing: 16) {
                    if showCount { Label("\(activities.count) activities", systemImage: "figure.mixed.cardio") }
                    if showDistance { Label(totalDistance, systemImage: "location") }
                    if showDuration { Label(totalTime, systemImage: "clock") }
                }.font(.callout.weight(.medium)).monospacedDigit()
            } else {
                HStack(spacing: 8) {
                    if showCount { SummaryCard(title: "ACTIVITIES", value: activities.count.formatted(), symbol: "figure.mixed.cardio") }
                    if showDistance { SummaryCard(title: "DISTANCE", value: totalDistance, symbol: "location") }
                    if showDuration { SummaryCard(title: "TIME", value: totalTime, symbol: "clock") }
                }
            }
            Divider()
            HStack(spacing: 16) {
                Toggle("Count", isOn: $showCount)
                Toggle("Distance", isOn: $showDistance)
                Toggle("Time", isOn: $showDuration)
                Toggle("Compact totals", isOn: $compactDashboard)
            }
        }
        .padding(16)
        .frame(width: 450, alignment: .leading)
        .background(HubTheme.background)
    }

    private func workspaceButton(_ title: String, page destination: String) -> some View {
        let isNew = (destination == "Compare" && !visitedCompare) || (destination == "Map" && !visitedMap)
        return Button { openWorkspace(destination) } label: {
            HStack(spacing: 5) {
                Text(title)
                if isNew {
                    Text("NEW").font(.system(size: 8, weight: .bold)).tracking(0.35)
                        .foregroundStyle(HubTheme.boardBackground)
                        .padding(.horizontal, 4).padding(.vertical, 2)
                        .background(HubTheme.plotPrimary, in: Capsule())
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(HubPillStyle(selected: page == destination))
        .accessibilityLabel(isNew ? "\(title), new" : title)
        .accessibilityAddTraits(page == destination ? .isSelected : [])
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(tourStep?.page == destination ? HubTheme.accent : .clear, lineWidth: 2).allowsHitTesting(false))
    }

    private func tourNeedsRecording(_ step: AppTourStep) -> Bool {
        switch step {
        case .charts, .laps, .zones, .stats: return model.selections.isEmpty
        case .pool: return !model.selections.contains { $0.sport == "swimming" && $0.subSport == "lapSwimming" }
        case .performance: return !model.selections.contains { $0.sessionIndex >= 0 && ["running", "cycling"].contains($0.sport) }
        case .route: return !model.selections.contains { $0.sessionIndex >= 0 && $0.isOutdoorRouteCandidate && ($0.distance ?? 0) > 0 }
        default: return false
        }
    }
    private func moveTour(_ offset: Int) {
        guard let current = tourStep, let next = AppTourStep(rawValue: current.rawValue + offset) else { return }
        showTourStep(next)
    }
    private func showTourStep(_ step: AppTourStep) {
        if step.section != nil {
            let eligible = model.selections.filter { activity in
                switch step {
                case .pool: return activity.sport == "swimming" && activity.subSport == "lapSwimming"
                case .performance: return activity.sessionIndex >= 0 && ["running", "cycling"].contains(activity.sport)
                case .route: return activity.sessionIndex >= 0 && activity.isOutdoorRouteCandidate && (activity.distance ?? 0) > 0
                default: return true
                }
            }
            if !eligible.contains(where: { $0.id == model.selectedID }) { model.selectedID = eligible.first?.id }
        }
        tourStep = step
        page = step.page
    }

    private func openWorkspace(_ destination: String) {
        if destination == "Map" { routeFocus = "" }
        page = destination
    }

    private func applyFilter() {
        page = "Activities"
        let groups = filteredGroups
        if !groups.contains(where: { $0.id == model.selectedID || $0.sessions.contains { $0.id == model.selectedID } }) {
            model.selectedID = groups.first?.id
        }
    }
    private func saveView() {
        let title = "\(sport) · \(days == 0 ? "All dates" : "\(days) days")\(search.isEmpty ? "" : " · \(search.prefix(40))") · \(sort)"
        guard !savedViews.contains(where: { $0.title == title }) else { return }
        saveViews(Array((savedViews + [SavedLibraryView(title: title, search: search, sport: sport, days: days, sort: sort)]).suffix(30)))
    }
    private func saveViews(_ views: [SavedLibraryView]) {
        if let data = try? JSONEncoder().encode(views), let json = String(data: data, encoding: .utf8) { savedViewsJSON = json }
    }
}

private struct FeedItem: Identifiable {
    let activity: Activity
    let title: String
    let detail: String
    let baseTitle: String
    let children: [FeedItem]?
    var id: String { activity.id }
}

struct SummaryCard: View {
    let title: String
    let value: String
    let symbol: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol).font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(HubTheme.muted)
            Text(value).font(.title2.bold()).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .hubPanel(padding: 14)
    }
}

func distance(_ meters: Double?) -> String { meters.map { String(format: "%.2f km", $0 / 1_000) } ?? "—" }
func duration(_ seconds: Double) -> String {
    let total = Int(seconds.rounded())
    return total >= 3_600 ? String(format: "%d:%02d:%02d", total / 3_600, total % 3_600 / 60, total % 60) : String(format: "%d:%02d", total / 60, total % 60)
}
func number(_ value: Double?, unit: String) -> String { value.map { String(format: "%.0f %@", $0, unit) } ?? "Not recorded" }
