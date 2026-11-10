import SwiftUI
import TrainingHubCore

enum DetailSection: String, CaseIterable, Identifiable {
    case charts = "Charts", laps = "Laps & splits", zones = "Zones", overview = "Overview", stats = "All stats", lengths = "Pool lengths"
    var id: String { rawValue }
}

struct IntervalPanel: View {
    let analysis: IntervalAnalysis
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Visible interval · \(duration(analysis.start))–\(duration(analysis.end))").font(.headline)
            HStack(spacing: 10) {
                SummaryCard(title: "ELAPSED", value: duration(analysis.elapsed), symbol: "clock")
                SummaryCard(title: "DISTANCE ESTIMATE", value: distance(analysis.distance), symbol: "location")
                SummaryCard(title: "TIME-WEIGHTED HR", value: number(analysis.heartRate.average, unit: "bpm"), symbol: "heart")
                SummaryCard(title: "TIME-WEIGHTED POWER", value: number(analysis.power.average, unit: "W"), symbol: "bolt")
            }
            Text("Recorded coverage: HR \(duration(analysis.heartRate.coveredSeconds)), power \(duration(analysis.power.coveredSeconds)). Gaps over 30 seconds are excluded. Distance interpolates only between nearby recorded points.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(.top, 8)
    }
}

struct LapAnalysisPanel: View {
    let laps: [AnalysisLap]
    let samples: [Sample]
    let focus: (AnalysisLap) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Laps & splits").font(.title3.bold())
            Text("Select a lap to zoom its interval in Charts. Pace uses recorded lap distance and timer time; HR is calculated from covered samples.")
                .font(.caption).foregroundStyle(.secondary)
            if laps.isEmpty { ContentUnavailableView("No recorded laps", systemImage: "flag.checkered") }
            else {
                Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 12) {
                    GridRow { Text("Leg / lap"); Text("Distance"); Text("Timer"); Text("Elapsed"); Text("Pace / speed"); Text("Avg HR*") }
                        .font(.caption.bold()).foregroundStyle(.secondary)
                    Divider().gridCellColumns(6)
                    ForEach(laps) { lap in
                        let hr = lap.start.flatMap { start in lap.end.map { Analysis.summary(samples, metric: .heartRate, start: start, end: $0).average } } ?? nil
                        GridRow {
                            Button("\(lap.leg) · \(lap.index)") { focus(lap) }
                                .buttonStyle(.link).disabled(lap.start == nil || lap.end == nil || (lap.end ?? 0) <= (lap.start ?? 0))
                            Text(distance(lap.distance))
                            Text(lap.timer.map(duration) ?? "—")
                            Text(lap.elapsed.map(duration) ?? "—")
                            Text(performance(lap.averageSpeed, sport: lap.sport))
                            Text(number(hr, unit: "bpm"))
                        }.font(.subheadline).monospacedDigit()
                    }
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}

struct RaceOverviewPanel: View {
    let activity: Activity
    let group: ActivityGroup?
    let select: (String) -> Void
    private var sessions: [Activity] { activity.id.hasPrefix(ActivityGroup.idPrefix) ? group?.sessions ?? [activity] : [activity] }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Activity breakdown").font(.title3.bold())
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 16) {
                GridRow { Text("Leg"); Text("Distance"); Text("Timer"); Text("Elapsed"); Text("Pace / speed"); Text("Avg HR") }
                    .font(.caption.bold()).foregroundStyle(.secondary)
                Divider().gridCellColumns(6)
                ForEach(sessions) { session in
                    let speed = session.distance.flatMap { distance in session.timer.flatMap { $0 > 0 ? distance / $0 : nil } }
                    GridRow {
                        Button(group?.legName(session) ?? session.displaySport) { select(session.id) }.buttonStyle(.link)
                        Text(distance(session.distance))
                        Text(session.timer.map(duration) ?? "—")
                        Text(duration(session.elapsed))
                        Text(performance(speed, sport: session.sport))
                        Text(number(session.avgHeartRate, unit: "bpm"))
                    }.font(.subheadline).monospacedDigit()
                }
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
            Text("Times and distances are recorded session summaries. Pace / speed is calculated from distance ÷ timer time. Transitions remain part of the total activity.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct ZonesPanel: View {
    let activity: Activity
    let samples: [Sample]
    let range: ClosedRange<Double>
    @State private var metric: Metric = .heartRate
    @State private var visibleRange = false
    @AppStorage private var hrBoundaries: String
    @AppStorage private var powerBoundaries: String

    init(activity: Activity, samples: [Sample], range: ClosedRange<Double>) {
        self.activity = activity; self.samples = samples; self.range = range
        _hrBoundaries = AppStorage(wrappedValue: "", "zones.\(activity.sport).heartRate")
        _powerBoundaries = AppStorage(wrappedValue: "", "zones.\(activity.sport).power")
    }
    private var input: Binding<String> { metric == .heartRate ? $hrBoundaries : $powerBoundaries }
    private var selectedRange: ClosedRange<Double> { visibleRange ? range : 0...activity.elapsed }
    private var boundaries: [Double]? { try? Analysis.parseZoneBoundaries(input.wrappedValue) }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Time in your zones").font(.title3.bold())
            Picker("Metric", selection: $metric) { Text("Heart rate").tag(Metric.heartRate); Text("Power").tag(Metric.power) }
                .pickerStyle(.segmented).frame(width: 300)
            HStack {
                Text("Boundaries (\(metric.unit))")
                TextField("Increasing values, separated by commas", text: input).textFieldStyle(.roundedBorder).frame(maxWidth: 380)
            }
            Text("Saved for \(activity.displaySport). Each boundary starts the next zone. Enter your own thresholds; no personal settings are assumed.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Use visible chart time interval", isOn: $visibleRange)
            if let boundaries {
                let result = Analysis.zones(samples, metric: metric, boundaries: boundaries, start: selectedRange.lowerBound, end: selectedRange.upperBound)
                ForEach(result.bins) { bin in
                    HStack(spacing: 16) {
                        Text("Z\(bin.id)").fontWeight(.semibold).frame(width: 30)
                        Text(zoneLabel(bin)).font(.caption).frame(width: 140, alignment: .leading)
                        ProgressView(value: result.coveredSeconds > 0 ? bin.seconds / result.coveredSeconds : 0).tint(zoneColor(bin.id))
                        Text(duration(bin.seconds)).monospacedDigit().frame(width: 72, alignment: .trailing)
                        Text(String(format: "%.1f%%", result.coveredSeconds > 0 ? bin.seconds / result.coveredSeconds * 100 : 0))
                            .monospacedDigit().frame(width: 60, alignment: .trailing)
                    }
                }
                Text("Recorded coverage \(duration(result.coveredSeconds)) · Uncovered \(duration(result.excludedSeconds)). Percentages use covered time. Recorded pauses may be included; gaps over 30 seconds and missing readings are excluded. These are local calculations, not Garmin timer-event zones.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if input.wrappedValue.isEmpty {
                ContentUnavailableView("Set your zone boundaries", systemImage: "slider.horizontal.3", description: Text("Enter 1–6 increasing thresholds to calculate zones locally."))
            } else { Text("Enter 1–6 positive, increasing numbers separated by commas.").font(.caption).foregroundStyle(.orange) }
        }.hubPanel()
    }
    private func zoneLabel(_ bin: ZoneBin) -> String {
        if let lower = bin.lower, let upper = bin.upper { return "\(String(format: "%g", lower))–<\(String(format: "%g", upper)) \(metric.unit)" }
        if let upper = bin.upper { return "<\(String(format: "%g", upper)) \(metric.unit)" }
        return "≥\(String(format: "%g", bin.lower ?? 0)) \(metric.unit)"
    }
    private func zoneColor(_ zone: Int) -> Color { [.gray, .blue, .teal, .orange, .red, .purple, .pink][min(zone - 1, 6)] }
}

func paceMinutes(_ minutes: Double) -> String {
    guard minutes.isFinite, minutes >= 0, minutes < 100_000 else { return "—" }
    return duration(minutes * 60)
}
func performance(_ speed: Double?, sport: String) -> String {
    guard let speed, speed > 0, speed.isFinite else { return "—" }
    if sport == "swimming" { return "\(paceMinutes(100 / speed / 60)) /100m" }
    if sport == "running" || sport == "walking" || sport == "hiking" { return "\(paceMinutes(1_000 / speed / 60)) /km" }
    return String(format: "%.1f km/h", speed * 3.6)
}
