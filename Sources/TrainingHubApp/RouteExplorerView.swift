import SwiftUI
import TrainingHubCore

struct RouteExplorerView: View {
    let groups: [ActivityGroup]
    let store: ActivityStore
    let openActivity: (String) -> Void
    @State private var days = 0
    @State private var sport = ""
    @State private var selectedID: String
    @AppStorage("map.showStreetBasemap") private var streets = true
    @AppStorage("map.trimIdleEdges") private var trimIdle = true
    @State private var heatmap: RouteHeatmap?
    @State private var loading = true
    @State private var error: String?

    init(groups: [ActivityGroup], store: ActivityStore, initialID: String, openActivity: @escaping (String) -> Void) {
        self.groups = groups
        self.store = store
        self.openActivity = openActivity
        _selectedID = State(initialValue: initialID)
    }

    var body: some View {
        let available = groups.filter { !$0.outdoorRouteSessions().isEmpty }
        let sportFilter = sport.isEmpty ? nil : sport
        let calendar = Calendar.current
        let earliest = days == 0 ? Date.distantPast :
            calendar.date(byAdding: .day, value: 1 - days, to: calendar.startOfDay(for: Date())) ?? Date.distantPast
        let eligible = available.filter { group in
            group.summary.start >= earliest && !group.outdoorRouteSessions(sport: sportFilter).isEmpty
        }
        let selected = eligible.filter { selectedID.isEmpty || $0.id == selectedID }
        let request = Request(ids: selected.map(\.id), sport: sport, trimIdle: trimIdle)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    HubEyebrow("Route explorer", color: HubTheme.accent)
                    Text("Your activity heatmap").hubHeading()
                }
                Text("See where your imported outdoor recordings overlap, or focus on a single route.")
                    .foregroundStyle(HubTheme.muted)
                HStack(spacing: 16) {
                    Picker("Period", selection: $days) {
                        Text("All time").tag(0)
                        Text("Last 30 days").tag(30)
                        Text("Last 90 days").tag(90)
                        Text("Last year").tag(365)
                    }.fixedSize()
                    Picker("Sport", selection: $sport) {
                        Text("All sports").tag("")
                        ForEach(Set(available.flatMap { $0.outdoorRouteSessions().map(\.sport) + [$0.summary.sport] }).sorted(), id: \.self) {
                            Text($0.capitalized).tag($0)
                        }
                    }.fixedSize()
                }
                Picker("Recording", selection: $selectedID) {
                    Text("All matching activities").tag("")
                    ForEach(eligible) { Text(activityMenuTitle($0.summary)).tag($0.id) }
                }.frame(maxWidth: 530)
                Toggle("Trim idle start & end", isOn: $trimIdle)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .help("Hide stationary GPS traces before and after movement. Mid-activity pauses and multisport transitions stay visible.")
                HStack {
                    if let heatmap, !loading {
                        Text("\(heatmap.activityCount.formatted()) outdoor \(heatmap.activityCount == 1 ? "activity" : "activities") with GPS")
                            .font(.callout.weight(.semibold)).monospacedDigit()
                    }
                    Spacer()
                    Toggle("Street basemap", isOn: $streets)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .help("Show Apple Maps streets. Turn off to use the offline map.")
                }
                if loading {
                    ProgressView("Building your heatmap locally…").frame(height: 300)
                        .frame(maxWidth: .infinity)
                } else if let error {
                    ContentUnavailableView("Couldn’t read the GPS tracks", systemImage: "exclamationmark.triangle", description: Text(error))
                        .frame(height: 240)
                } else if let heatmap, let bounds = heatmap.bounds {
                    RouteMapInspection(heatmap: heatmap, bounds: bounds, streets: streets, groups: selected,
                                       openActivity: openActivity) { heatLegend }
                    .id(request)
                } else {
                    ContentUnavailableView("No outdoor GPS tracks in this selection", systemImage: "map",
                        description: Text("Try a wider period, a different sport or an outdoor recording. Indoor and virtual sessions are excluded."))
                        .frame(height: 240)
                }
                Text("Only outdoor GPS tracks contribute. Brighter trails show more overlapping activities at the current zoom.")
                    .font(.caption).foregroundStyle(HubTheme.muted)
                HStack(spacing: 6) {
                    Image(systemName: "lock.shield")
                    Text("GPS tracks stay on this Mac. Apple Maps can receive the area you view when the street basemap is on.")
                    Link("Apple Maps privacy", destination: URL(string: "https://www.apple.com/legal/privacy/data/en/apple-maps/")!)
                }.font(.caption).foregroundStyle(HubTheme.muted)
            }.padding(.vertical, 8)
        }
        .onChange(of: days) { selectedID = "" }
        .onChange(of: sport) { selectedID = "" }
        .onChange(of: available.map(\.id)) {
            if !available.contains(where: { $0.id == selectedID }) { selectedID = "" }
        }
        .task(id: request) {
            loading = true
            error = nil
            defer { if !Task.isCancelled { loading = false } }
            do {
                let result = try await store.routeHeatmap(groups: selected, sport: request.sport.isEmpty ? nil : request.sport,
                                                          trimIdle: request.trimIdle)
                try Task.checkCancellation()
                heatmap = result
            } catch is CancellationError {
                return
            } catch {
                if !Task.isCancelled { self.error = error.localizedDescription }
            }
        }
    }

    private struct Request: Hashable {
        let ids: [String]
        let sport: String
        let trimIdle: Bool
    }

    private var heatLegend: some View {
        HStack(spacing: 9) {
            Text("Fewer activities")
            Capsule()
                .fill(LinearGradient(colors: [1.0, 2, 4, 7, 10].map { density in
                    let ink = RouteHeatRaster.ink(at: density)
                    return Color(red: ink.red, green: ink.green, blue: ink.blue)
                }, startPoint: .leading, endPoint: .trailing))
                .frame(width: 116, height: 7)
                .accessibilityHidden(true)
            Text("More activities")
        }.font(.caption).foregroundStyle(HubTheme.muted)
            .accessibilityElement(children: .combine)
    }
}
