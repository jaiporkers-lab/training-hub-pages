import SwiftUI
import Charts
import TrainingHubCore

struct PerformancePanel: View {
    let activity: Activity
    let samples: [Sample]
    let all: [Activity]
    let store: ActivityStore
    @State private var curve: [PowerEffort] = []
    @State private var efforts: [DistanceEffort] = []
    @State private var splits: [RunningSplit] = []
    @State private var steady: SteadyEffort?
    @State private var baseline: SteadyEffort?
    @State private var comparisonID = ""
    @State private var from = 0.0
    @State private var to = 1.0
    @State private var error: String?
    @State private var calculating = false
    @AppStorage("zones.cycling.ftp") private var ftp = 0.0
    private var range: ClosedRange<Double> { (from * activity.elapsed)...(to * activity.elapsed) }
    private var calculationID: String { "\(samples.count)-\(comparisonID)-\(from)-\(to)" }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if calculating { ProgressView("Calculating recorded efforts…") }
            if let error { Text(error).foregroundStyle(.red) }
            if activity.sport == "cycling" { powerContent }
            else { runningContent }
        }
        .task(id: samples.count) {
            calculating = true
            defer { if !Task.isCancelled { calculating = false } }
            let data = samples, cycling = activity.sport == "cycling"
            let job = Task.detached(priority: .userInitiated) {
                if cycling { return (try PerformanceAnalysis.powerCurve(data), [DistanceEffort](), [RunningSplit]()) }
                return ([PowerEffort](), try PerformanceAnalysis.bestDistanceEfforts(data), PerformanceAnalysis.runningSplits(data))
            }
            do {
                let result = try await withTaskCancellationHandler(operation: { try await job.value }, onCancel: { job.cancel() })
                guard !Task.isCancelled else { return }
                curve = result.0; efforts = result.1; splits = result.2
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
        .task(id: calculationID) {
            guard activity.sport == "running" else { return }
            do {
                let data = samples, bounds = range
                let other = comparisonID.isEmpty ? [] : try await store.samples(for: comparisonID)
                let otherElapsed = all.first { $0.id == comparisonID }?.elapsed ?? 0
                let startFraction = from, endFraction = to
                let job = Task.detached(priority: .userInitiated) {
                    (PerformanceAnalysis.steadyEffort(data, start: bounds.lowerBound, end: bounds.upperBound),
                     other.isEmpty ? nil : PerformanceAnalysis.steadyEffort(other, start: startFraction * otherElapsed, end: endFraction * otherElapsed))
                }
                let result = await withTaskCancellationHandler(operation: { await job.value }, onCancel: { job.cancel() })
                guard !Task.isCancelled else { return }
                steady = result.0; baseline = result.1
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
    private var powerContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Power duration").font(.title2.bold())
            Text("Best continuously recorded average power, from 5 seconds to 60 minutes. Missing readings and gaps over 30 seconds break an effort. Recorded zero power counts.")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Text("Your FTP")
                TextField("Watts", value: $ftp, format: .number.precision(.fractionLength(0))).frame(width: 85).textFieldStyle(.roundedBorder)
                Text("W · 0 turns off FTP percentages").font(.caption).foregroundStyle(.secondary)
            }.onChange(of: ftp) { ftp = ftp.isFinite ? min(2_000, max(0, ftp)) : 0 }
            if curve.contains(where: { $0.watts != nil }) {
                HubChartBoard(title: "Best efforts", subtitle: "Recorded watts · duration on a logarithmic axis") {
                    Chart(curve.filter { $0.watts != nil }) { effort in
                        LineMark(x: .value("Seconds", effort.seconds), y: .value("Watts", effort.watts!)).foregroundStyle(HubTheme.plotPrimary)
                        PointMark(x: .value("Seconds", effort.seconds), y: .value("Watts", effort.watts!)).foregroundStyle(HubTheme.plotPrimary)
                    }
                    .chartXScale(domain: 5.0...3_600.0, type: .log)
                    .chartYAxisLabel("W").chartXAxisLabel("seconds")
                    .chartOverlay { proxy in
                        ChartInspectionOverlay(proxy: proxy, reset: activity.id) { (x: Double) in
                            if let effort = curve.min(by: { abs(log($0.seconds / max(1, x))) < abs(log($1.seconds / max(1, x))) }) {
                                Text(duration(effort.seconds)).bold()
                                Text(number(effort.watts, unit: "W"))
                                if ftp > 0, let watts = effort.watts { Text(String(format: "%.0f%% FTP", watts / ftp * 100)) }
                                if let start = effort.start { Text("From \(duration(start))") }
                            }
                        }
                    }.frame(height: 250)
                }
            } else { ContentUnavailableView("No continuous power efforts", systemImage: "bolt.slash", description: Text("This recording needs at least five seconds of covered power data.")) }
            Grid(alignment: .leading, horizontalSpacing: 35, verticalSpacing: 10) {
                GridRow { Text("Duration"); Text("Best average"); Text("% FTP"); Text("Starts at") }.font(.caption.bold()).foregroundStyle(.secondary)
                ForEach(curve) { point in
                    GridRow {
                        Text(duration(point.seconds)); Text(number(point.watts, unit: "W"))
                        Text(ftp > 0 ? point.watts.map { String(format: "%.0f%%", $0 / ftp * 100) } ?? "—" : "—")
                        Text(point.start.map(duration) ?? "—")
                    }.monospacedDigit()
                }
            }.hubPanel()
            Text("Power holds the last reading until the next sample, for up to 30 seconds. This is a recorded best-effort curve, not an FTP estimate.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private var runningContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Running consistency").font(.title2.bold())
            Text("Choose a steady section to compare pace and heart rate. Drift needs at least 10 minutes and 80% jointly recorded speed/HR coverage in each half.").font(.callout).foregroundStyle(.secondary)
            HStack {
                Text("From \(duration(range.lowerBound))").frame(width: 120, alignment: .leading)
                Slider(value: $from, in: 0...max(0, to - 0.001))
                Text("To \(duration(range.upperBound))").frame(width: 120, alignment: .leading)
                Slider(value: $to, in: min(1, from + 0.001)...1)
                Button("Whole run") { from = 0; to = 1 }
            }
            Picker("Compare steady effort", selection: $comparisonID) {
                Text("Choose another run").tag("")
                ForEach(all.filter { $0.id != activity.id && $0.sport == "running" && $0.sessionIndex >= 0 }) {
                    Text(activityMenuTitle($0)).tag($0.id)
                }
            }.frame(maxWidth: 600)
            HStack(alignment: .top, spacing: 14) {
                steadyCard("Selected run", steady)
                if !comparisonID.isEmpty { steadyCard("Comparison run", baseline) }
            }
            Text("The same percentage range is used for both runs. Drift = change in speed/HR efficiency between equal elapsed halves; positive means efficiency fell. Speed variation is the weighted within-half coefficient of variation. Pauses below 0.5 m/s are uncovered. Terrain, heat and fatigue are not adjusted.")
                .font(.caption).foregroundStyle(.secondary)
            if !splits.isEmpty {
                HubChartBoard(title: "Kilometre splits", subtitle: "Elapsed pace · final split may be partial") {
                    Chart(splits) { split in
                        BarMark(x: .value("Split", split.number), y: .value("min/km", split.secondsPerKilometer / 60)).foregroundStyle(HubTheme.plotPrimary)
                    }.chartYAxisLabel("min/km")
                    .chartOverlay { proxy in
                        ChartInspectionOverlay(proxy: proxy, reset: activity.id) { (x: Int) in
                            if let split = splits.first(where: { $0.number == x }) {
                                Text("Split \(split.number) · \(distance(split.meters))").bold()
                                Text("\(paceMinutes(split.secondsPerKilometer / 60)) /km")
                                Text("HR \(number(split.heartRate, unit: "bpm")) · \(Int(split.heartRateCoverage * 100))% covered")
                            }
                        }
                    }.frame(height: 230)
                }
                Grid(alignment: .leading, horizontalSpacing: 25, verticalSpacing: 9) {
                    GridRow { Text("Split"); Text("Distance"); Text("Elapsed pace"); Text("Heart rate"); Text("HR coverage") }.font(.caption.bold()).foregroundStyle(.secondary)
                    ForEach(splits) { split in
                        GridRow {
                            Text("\(split.number)"); Text(distance(split.meters)); Text("\(paceMinutes(split.secondsPerKilometer / 60)) /km")
                            Text(number(split.heartRate, unit: "bpm")); Text(String(format: "%.0f%%", split.heartRateCoverage * 100))
                        }.monospacedDigit()
                    }
                }.hubPanel()
            } else { Text("No continuous distance splits available.").foregroundStyle(.secondary) }
            Text("Best recorded distance efforts").font(.headline)
            ForEach(efforts) { effort in
                HStack { Text(distance(effort.meters)); Spacer(); Text(effort.seconds.map(duration) ?? "Insufficient continuous distance"); Text(effort.start.map { "from \(duration($0))" } ?? "").foregroundStyle(.secondary) }.monospacedDigit()
            }
            Text("Distance efforts interpolate recorded distance. Elapsed time includes pauses inside an effort. Gaps over 30 seconds and distance resets break an effort; splits crossing those gaps stay unavailable.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private func steadyCard(_ title: String, _ result: SteadyEffort?) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.headline)
            Text("Pace  \(performance(result?.averageSpeed, sport: "running"))")
            Text("Heart rate  \(number(result?.averageHeartRate, unit: "bpm"))")
            Text("Paired coverage  \(Int((result?.coverage ?? 0) * 100))%")
            Text("HR drift  \(result?.driftPercent.map { String(format: "%+.1f%%", $0) } ?? "Needs more covered time")")
            Text("Speed variation  \(result?.paceVariationPercent.map { String(format: "%.1f%%", $0) } ?? "—")")
        }.font(.callout).monospacedDigit().frame(maxWidth: .infinity, alignment: .leading).hubPanel()
    }
}
