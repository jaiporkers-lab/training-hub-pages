import SwiftUI
import TrainingHubCore

struct ActivityComparisonView: View {
    let groups: [ActivityGroup]
    let preferredID: String?
    let store: ActivityStore?
    let openActivity: (String) -> Void
    @State private var selectedID = ""
    @State private var baselineID = ""
    @State private var timerBasis = false
    @State private var graphLegID = ""
    private var selected: ActivityGroup? { groups.first { $0.id == selectedID } }
    private var candidates: [ActivityGroup] {
        guard let selected else { return [] }
        return groups.filter { compatible(selected, $0) }
    }
    private var baseline: ActivityGroup? { candidates.first { $0.id == baselineID } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    HubEyebrow("Side by side", color: HubTheme.accent)
                    Text("Compare activities").hubHeading()
                }
                Text("Overlay two recordings, inspect their sensor readings and compare matched legs.").foregroundStyle(.secondary)
                Picker("Selected", selection: $selectedID) {
                    Text("Choose activity").tag("")
                    ForEach(groups) { Text(activityMenuTitle($0.summary)).tag($0.id) }
                }
                Picker("Baseline", selection: $baselineID) {
                    Text("Choose baseline").tag("")
                    ForEach(candidates) { Text(activityMenuTitle($0.summary)).tag($0.id) }
                }.disabled(candidates.isEmpty)
                if let selected, let baseline {
                    let lhs = selected.summary, rhs = baseline.summary
                    let legs = ActivityComparison.legs(selected: selected, baseline: baseline)
                    let matched = legs.filter { $0.selected != nil && $0.baseline != nil }
                    if let store {
                        if selected.isMultisport {
                            Picker("Graph scope", selection: $graphLegID) {
                                Text("Whole activity").tag("")
                                ForEach(matched) { Text($0.title).tag($0.id) }
                            }.fixedSize()
                        }
                        let leg = matched.first { $0.id == graphLegID }
                        let left = leg?.selected ?? lhs
                        let right = leg?.baseline ?? rhs
                        ComparisonGraph(store: store, selected: left, baseline: right,
                                        selectedGroup: selected, baselineGroup: baseline)
                            .id([left.id, right.id])
                    }
                    Text("Time and distance").font(.title3.bold())
                    Picker("Time basis", selection: $timerBasis) {
                        Text("Elapsed time").tag(false)
                        Text("Recorded timer").tag(true)
                    }.pickerStyle(.segmented).frame(width: 320)
                    HStack(spacing: 12) {
                        SummaryCard(title: "SELECTED TIME", value: time(lhs), symbol: "stopwatch")
                        SummaryCard(title: "BASELINE TIME", value: time(rhs), symbol: "clock.arrow.circlepath")
                        SummaryCard(title: "TIME DIFFERENCE", value: timeDifference(timerBasis ? lhs.timer.flatMap { a in rhs.timer.map { a - $0 } } : lhs.elapsed - rhs.elapsed), symbol: "plus.forwardslash.minus")
                    }
                    Text("Selected − baseline. A negative time difference means less recorded time; it does not establish a faster performance when distances, routes or conditions differ.")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 20) {
                        Label("Selected: \(distance(lhs.distance))", systemImage: "location")
                        Text("Baseline: \(distance(rhs.distance))")
                    }.font(.callout)
                    LegDurationBars(legs: legs, timerBasis: timerBasis)
                    Text("Leg comparison").font(.headline)
                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 14) {
                        GridRow {
                            Text("Leg").bold(); Text("Selected").bold(); Text("Baseline").bold(); Text("Time Δ").bold(); Text("Distance Δ").bold()
                        }
                        ForEach(legs) { leg in
                            GridRow {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(leg.title).fontWeight(.semibold)
                                    if let activity = leg.selected { Button("Open leg") { openActivity(activity.id) }.buttonStyle(.link).font(.caption) }
                                }
                                Text(leg.selected.map(time) ?? "Missing leg")
                                Text(leg.baseline.map(time) ?? "Missing leg")
                                Text(timeDifference(timerBasis ? leg.timerDifference : leg.elapsedDifference))
                                Text(leg.distanceDifference.map { String(format: "%+.2f km", $0 / 1_000) } ?? "—")
                            }
                        }
                    }.font(.callout).monospacedDigit().frame(maxWidth: .infinity, alignment: .leading)
                        .hubPanel(padding: 18)
                    Text("Legs are matched by sport and occurrence (including T1/T2). Unmatched legs and missing timer/distance values remain unavailable. Elapsed time includes pauses; timer values are shown only when recorded.")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Open selected activity") { openActivity(lhs.id) }
                        Button("Open baseline activity") { openActivity(rhs.id) }
                        Button("Swap activities") { let old = selectedID; selectedID = baselineID; baselineID = old }
                    }
                } else {
                    ContentUnavailableView("Choose two activities", systemImage: "arrow.left.arrow.right", description: Text(candidates.isEmpty && selected != nil ? "No other compatible activity is imported. Choose another sport or import more history. Multisport recordings compare with other multisport recordings." : "Select an activity and a compatible baseline."))
                        .frame(height: 200)
                }
            }.padding(.vertical, 8)
        }
        .onAppear {
            guard selectedID.isEmpty else { return }
            let preferred = groups.first { $0.id == preferredID }
            let comparable = groups.first { group in groups.contains { compatible(group, $0) } }
            selectedID = (preferred.flatMap { group in groups.contains { compatible(group, $0) } ? group : nil }
                          ?? comparable ?? preferred ?? groups.first)?.id ?? ""
            baselineID = candidates.first?.id ?? ""
        }
        .onChange(of: selectedID) {
            if !candidates.contains(where: { $0.id == baselineID }) { baselineID = candidates.first?.id ?? "" }
            graphLegID = ""
        }
        .onChange(of: baselineID) { graphLegID = "" }
    }
    private func compatible(_ left: ActivityGroup, _ right: ActivityGroup) -> Bool {
        left.id != right.id && left.isMultisport == right.isMultisport &&
            (left.isMultisport || left.summary.sport == right.summary.sport)
    }

    private func time(_ activity: Activity) -> String { timerBasis ? activity.timer.map(duration) ?? "Not recorded" : duration(activity.elapsed) }
    private func timeDifference(_ value: Double?) -> String {
        guard let value else { return "—" }
        return (value < 0 ? "−" : value > 0 ? "+" : "") + duration(abs(value))
    }
}
