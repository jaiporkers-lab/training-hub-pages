import SwiftUI
import AppKit
import TrainingHubCore

struct ActivityDetail: View {
    let activity: Activity
    let all: [Activity]
    let store: ActivityStore
    let group: ActivityGroup?
    let groups: [ActivityGroup]
    let selectActivity: (String) -> Void
    let openRoute: () -> Void
    @State private var samples: [Sample] = []
    @State private var plotted: [PlotPoint] = []
    @State private var maximumDistance = 0.1
    @State private var sampleIndex = SampleInspectionIndex()
    @State private var comparisonIndex = SampleInspectionIndex()
    @State private var comparison: [Sample] = []
    @State private var compareID = ""
    @State private var metric: Metric = .heartRate
    @State private var distanceAxis = false
    @State private var lower = 0.0
    @State private var upper = 1.0
    @State private var error: String?
    @State private var loading = false
    @State private var section: DetailSection = .charts
    @State private var smoothing = 0.0
    @State private var exportError: String?
    @State private var lastExport: URL?
    @State private var initialMetricChosen = false

    private var other: Activity? { all.first { $0.id == compareID } }
    private var otherGroup: ActivityGroup? {
        guard let other else { return nil }
        return groups.first { $0.summary.fileHash == other.fileHash }
    }
    private var wholeRace: Bool { activity.id.hasPrefix(ActivityGroup.idPrefix) }
    private var maxX: Double {
        distanceAxis ? maximumDistance : max(activity.elapsed, samples.last?.elapsed ?? 0, comparison.last?.elapsed ?? 0, 6) / 60
    }
    private var chartUnit: String { metric == .pace && activity.sport == "swimming" ? "min/100m" : metric.unit }
    private var laps: [AnalysisLap] { Analysis.laps(activity: activity, group: group) }
    private var timeRange: ClosedRange<Double> {
        let from = distanceAxis ? 0 : min(activity.elapsed, max(0, maxX * lower * 60))
        let to = distanceAxis ? activity.elapsed : min(activity.elapsed, max(from, maxX * upper * 60))
        return from...to
    }
    private var domain: ClosedRange<Double> { maxX * lower...maxX * upper }
    private func rebuildPlot(reindex: Bool = false) {
        if reindex {
            sampleIndex = SampleInspectionIndex(samples: samples, distanceAxis: distanceAxis)
            comparisonIndex = SampleInspectionIndex(samples: comparison, distanceAxis: distanceAxis)
        }
        plotted = points(samples, series: "Selected", prefix: "a") + points(comparison, series: "Comparison", prefix: "b")
    }
    private func points(_ data: [Sample], series: String, prefix: String) -> [PlotPoint] {
        let plotActivity = prefix == "a" ? activity : (other ?? activity)
        return activityPlotPoints(data, activity: plotActivity, group: prefix == "a" ? group : otherGroup,
                                  metric: metric, distanceAxis: distanceAxis, smoothing: smoothing,
                                  series: series, prefix: prefix)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                activityHeader
                if let group, group.isMultisport {
                    ScrollView(.horizontal) {
                        HStack(spacing: 5) {
                            legButton("Entire activity", id: group.id)
                            ForEach(group.sessions) { leg in
                                legButton("\(group.legName(leg)) · \(duration(leg.elapsed))", id: leg.id)
                            }
                        }.padding(.vertical, 1)
                    }.scrollIndicators(.hidden)
                }
                HStack(alignment: .top, spacing: 16) {
                    headlineStat("Distance", distance(activity.distance))
                    headlineStat("Elapsed", duration(activity.elapsed))
                    headlineStat("Timer", activity.timer.map(duration) ?? "—")
                    headlineStat("Avg. heart rate", activity.avgHeartRate.map { number($0, unit: "bpm") } ?? "—")
                    headlineStat("Avg. power", activity.avgPower.map { number($0, unit: "W") } ?? "—")
                }.hubPanel(padding: 11)
                Picker("Analysis", selection: $section) {
                    ForEach(DetailSection.allCases.filter { $0 != .lengths || activity.sport == "swimming" }) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).labelsHidden()
                if let lastExport {
                    Button("CSV exported · Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([lastExport]) }
                        .buttonStyle(.link).font(.caption)
                }
                if section == .charts {
                    HStack {
                        Picker("Metric", selection: $metric) {
                            ForEach(Metric.allCases) { Text($0.rawValue).tag($0) }
                        }.frame(maxWidth: 240)
                        Picker("Smoothing", selection: $smoothing) {
                            Text("Raw").tag(0.0); Text("5 sec").tag(5.0); Text("15 sec").tag(15.0); Text("30 sec").tag(30.0)
                        }.frame(maxWidth: 190)
                        Picker("Align by", selection: $distanceAxis) {
                            Text("Elapsed time").tag(false)
                            Text("Distance").tag(true)
                        }.frame(maxWidth: 240)
                    }
                    let comparisons = all.filter { $0.id != activity.id && $0.sport == activity.sport }
                    if !comparisons.isEmpty {
                        Picker("Compare with", selection: $compareID) {
                            Text("No comparison").tag("")
                            ForEach(comparisons) { Text(activityMenuTitle($0)).tag($0.id) }
                        }.frame(maxWidth: 520)
                    }
                    if let error { Text(error).foregroundStyle(.red) }
                    if loading { ProgressView("Reading local samples…") }
                    if plotted.isEmpty && !loading {
                        ContentUnavailableView("No recorded \(metric.rawValue.lowercased())", systemImage: "sensor", description: Text("Select another metric or axis. Missing sensor data is kept empty."))
                            .frame(height: 260)
                    } else {
                        ActivityPlot(activity: activity, comparisonActivity: other, group: group, comparisonGroup: otherGroup, samples: samples, comparison: comparison, sampleIndex: sampleIndex, comparisonIndex: comparisonIndex, plot: plotted, metric: metric, distanceAxis: distanceAxis, smoothing: smoothing, domain: domain, chartUnit: chartUnit)
                        HStack {
                            Text("View from").font(.caption)
                            Slider(value: $lower, in: 0...max(0, upper - 0.0001))
                            Text("to").font(.caption)
                            Slider(value: $upper, in: min(1, lower + 0.0001)...1)
                            Button("Reset") { lower = 0; upper = 1 }
                        }
                        Text("Hover, click or drag across the chart to inspect · Adjust the range to analyse an interval · \(chartUnit)\(smoothing > 0 ? " · Centred sample mean; statistics use raw data" : "")")
                            .font(.caption).foregroundStyle(.secondary)
                        if !distanceAxis {
                            IntervalPanel(analysis: Analysis.interval(samples, start: timeRange.lowerBound, end: timeRange.upperBound))
                        } else {
                            Text("Select elapsed time to analyse a time interval.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if let other {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Selected − comparison").font(.headline)
                            Text("Distance \(delta(activity.distance, other.distance, scale: 0.001, unit: "km"))  ·  Timer \(delta(activity.timer, other.timer, scale: 1 / 60, unit: "min"))  ·  Avg HR \(delta(activity.avgHeartRate, other.avgHeartRate, unit: "bpm"))")
                                .font(.subheadline).monospacedDigit()
                            Text("Overlay uses elapsed time or recorded distance. Terrain, pauses and conditions are not adjusted.")
                                .font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading).hubPanel(padding: 14)
                    }
                } else if section == .stats {
                    AllStatsView(activity: activity, group: group, store: store)
                } else if section == .lengths {
                    PoolLengthsView(activity: activity, store: store)
                } else if section == .laps {
                    LapAnalysisPanel(laps: laps, samples: samples, focus: focusLap)
                } else if section == .zones {
                    ZonesPanel(activity: activity, samples: samples, range: timeRange)
                } else {
                    RaceOverviewPanel(activity: activity, group: group, select: selectActivity)
                }
                Text(wholeRace ? "The race clock includes transitions and gaps between legs. Distance adds leg totals. Whole-activity averages are local time-weighted estimates from available leg summaries; missing leg averages stay unavailable. Dashed chart lines mark leg boundaries." : "Summary averages come from the FIT session. Timer time and elapsed time remain distinct. Original FIT files are retained for future analysis.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(.top, 3).padding(.bottom, 8)
        }
        .task(id: compareID) {
            loading = true
            error = nil
            comparison = []
            if initialMetricChosen { rebuildPlot(reindex: true) }
            defer { if !Task.isCancelled { loading = false } }
            do {
                let primary: [Sample]
                if initialMetricChosen { primary = samples }
                else { primary = try await store.samples(for: activity.id) }
                let secondary = compareID.isEmpty ? [] : try await store.samples(for: compareID)
                guard !Task.isCancelled else { return }
                samples = primary
                comparison = secondary
                let primaryDistance = primary.lazy.compactMap(\.distance).max() ?? 0
                let secondaryDistance = secondary.lazy.compactMap(\.distance).max() ?? 0
                maximumDistance = max(0.1, max(primaryDistance, secondaryDistance) / 1_000)
                if !initialMetricChosen {
                    let preferred: Metric = ["running", "swimming"].contains(activity.sport) ? .pace : .heartRate
                    metric = ActivityGraph.preferredMetric(preferred, selected: primary, baseline: [])
                    initialMetricChosen = true
                }
                rebuildPlot(reindex: true)
                error = nil
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
        .onChange(of: metric) { rebuildPlot() }
        .onChange(of: smoothing) { rebuildPlot() }
        .onChange(of: distanceAxis) { rebuildPlot(reindex: true) }
        .alert("Export failed", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("OK") { exportError = nil }
        } message: { Text(exportError ?? "") }
    }

    private var activityHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                let date = activity.start.formatted(date: .abbreviated, time: .omitted)
                HubEyebrow("\(activity.displaySport) · \(date)\(activity.isDemo ? " · Synthetic" : "")", color: HubTheme.accent)
                Text(activity.title).hubHeading(size: 26).lineLimit(2)
                Text("\(activity.sampleCount.formatted()) samples · \(activity.laps.count) laps")
                    .font(.caption).foregroundStyle(HubTheme.muted)
            }
            Spacer()
            if group.map({ !$0.outdoorRouteSessions().isEmpty }) ?? activity.isOutdoorRouteCandidate {
                Button(action: openRoute) { Label("Map", systemImage: "map") }.fixedSize()
            }
            Menu {
                Button("Sensor data CSV") { exportCSV(CSVExport.samples(samples), name: "\(activity.title)-sensors.csv") }
                    .disabled(samples.isEmpty)
                Button("Laps & splits CSV") { exportCSV(CSVExport.laps(laps), name: "\(activity.title)-laps.csv") }
                    .disabled(laps.isEmpty)
            } label: { Label("Export", systemImage: "square.and.arrow.up") }
            .fixedSize()
        }
    }

    private func legButton(_ title: String, id: String) -> some View {
        Button(title) { selectActivity(id) }
            .buttonStyle(HubPillStyle(selected: activity.id == id))
            .accessibilityAddTraits(activity.id == id ? .isSelected : [])
    }

    private func headlineStat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(HubTheme.muted)
            Text(value).font(.callout.weight(.semibold)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    @MainActor
    private func exportCSV(_ text: String, name: String) {
        Task {
            do {
                let url = try await store.exportCSV(text, suggestedName: name)
                lastExport = url
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            catch { exportError = error.localizedDescription }
        }
    }

    private func focusLap(_ lap: AnalysisLap) {
        guard let from = lap.start, let to = lap.end, to > from else { return }
        let seconds = max(activity.elapsed, samples.last?.elapsed ?? 0, comparison.last?.elapsed ?? 0, 6)
        distanceAxis = false
        lower = max(0, min(0.9999, from / seconds))
        upper = min(1, max(lower + 0.0001, to / seconds))
        section = .charts
    }

    private func delta(_ lhs: Double?, _ rhs: Double?, scale: Double = 1, unit: String) -> String {
        guard let lhs, let rhs else { return "—" }
        return String(format: "%+.1f %@", (lhs - rhs) * scale, unit)
    }
}
