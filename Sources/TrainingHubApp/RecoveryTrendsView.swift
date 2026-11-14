import SwiftUI
import Charts
import TrainingHubCore

struct RecoveryTrendsView: View {
    @ObservedObject var model: HubModel
    @State private var metricID = "hrv"
    @State private var days = 90
    @State private var lag = 0
    @State private var report: RecoveryTrends?
    private var metric: HealthMetric { HealthMetric.all.first { $0.id == metricID }! }
    private var key: String { "\(metricID)-\(days)-\(lag)-\(model.activities.count)-\(model.health.updated?.timeIntervalSince1970 ?? 0)" }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HubEyebrow("Recorded patterns", color: HubTheme.accent)
                Text("Recovery & training").hubHeading()
                HStack {
                    Picker("Health metric", selection: $metricID) { ForEach(HealthMetric.all) { Text($0.title).tag($0.id) } }.frame(maxWidth: 350)
                    Picker("History", selection: $days) { Text("28 days").tag(28); Text("90 days").tag(90); Text("180 days").tag(180); Text("1 year").tag(365) }.frame(width: 160)
                    Button("Sync last 60 health days") { model.syncHealth(days: 30) }
                        .disabled(!model.keyAvailable || model.busy || model.syncing || model.healthSyncing || model.testingConnection)
                }
                Text("Daily training volume aligned with your saved health history. The blue trend is a 7-day mean of available readings. Today is excluded; missing health readings remain empty.").font(.callout).foregroundStyle(.secondary)
                if let report {
                    HStack(spacing: 14) {
                        SummaryCard(title: "LAST 7 DAYS · \(report.recentDays)/7", value: formattedHealthValue(report.recentMean, metric: metric), symbol: "heart")
                        SummaryCard(title: "PREVIOUS 28 DAYS · \(report.previousDays)/28", value: formattedHealthValue(report.previousMean, metric: metric), symbol: "clock.arrow.circlepath")
                        SummaryCard(title: "CHANGE IN DAILY MEAN", value: difference(report), symbol: "waveform.path")
                    }
                    alignedCharts(report)
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Explore an association").font(.headline)
                        Picker("Pair training volume with", selection: $lag) { Text("Same-day health").tag(0); Text("Next-day health").tag(1) }.pickerStyle(.segmented).frame(maxWidth: 400)
                        HStack(spacing: 20) {
                            Text(report.association.map { String(format: "r = %+.2f", $0) } ?? "Not enough varied paired days").font(.title3.bold()).monospacedDigit()
                            Text("\(report.pairs) paired days").foregroundStyle(.secondary)
                        }
                        Text("Pearson correlation needs at least 10 paired days and variation in both measures. This shows a descriptive association, not causation or a recovery recommendation. A day without an imported activity counts as zero imported training, which may differ from your actual training.").font(.caption).foregroundStyle(.secondary)
                    }.hubPanel()
                    if report.points.allSatisfy({ $0.health == nil }) {
                        ContentUnavailableView("No saved \(metric.title.lowercased()) in this range", systemImage: "heart.text.square", description: Text("Sync health or select a metric supported by your Garmin device. Longer charts use history already saved on this Mac."))
                    }
                    Text("Training volume sums timer time, falling back to elapsed time, and is assigned to each recording’s start date. Transitions count once within a multisport recording. Sleep uses Garmin’s calendar date. A rolling mean can contain 1–7 readings; hover to see its coverage.").font(.caption).foregroundStyle(.secondary)
                } else { ProgressView("Aligning local history…") }
            }.padding(.vertical, 8)
        }
        .task(id: key) {
            let activities = model.activities, health = model.health.days, metric = metric, count = days, delay = lag
            let job = Task.detached(priority: .userInitiated) { RecoveryTrends.make(activities: activities, health: health, metric: metric, days: count, lag: delay) }
            let result = await withTaskCancellationHandler(operation: { await job.value }, onCancel: { job.cancel() })
            if !Task.isCancelled { report = result }
        }
    }
    private func difference(_ report: RecoveryTrends) -> String {
        guard let recent = report.recentMean, let previous = report.previousMean else { return "—" }
        return String(format: "%+.2f %@", recent - previous, metric.unit)
    }
    private func alignedCharts(_ report: RecoveryTrends) -> some View {
        let domain = report.points.first!.date...report.points.last!.date
        // Distinct series prevent missing health days from being joined.
        let segments = healthSegments(report.points)
        return VStack(spacing: 12) {
            HubChartBoard(title: metric.title, subtitle: "Daily readings & local 7-day mean") {
                Chart {
                    ForEach(segments) { point in
                        LineMark(x: .value("Date", point.date), y: .value(metric.unit, point.value), series: .value("Continuous days", point.segment)).foregroundStyle(HubTheme.boardMuted)
                        PointMark(x: .value("Date", point.date), y: .value(metric.unit, point.value)).foregroundStyle(HubTheme.boardMuted)
                    }
                    ForEach(report.points.filter { $0.rollingAverage != nil }) { point in
                        LineMark(x: .value("Date", point.date), y: .value("7-day mean", point.rollingAverage!), series: .value("Rolling span", rollingSegment(point, in: report.points))).foregroundStyle(HubTheme.plotPrimary)
                    }
                }.chartXScale(domain: domain).chartYScale(domain: .automatic(includesZero: false)).chartYAxisLabel(metric.unit)
                    .chartOverlay { proxy in inspector(proxy, report) }.frame(height: 230)
            }
            HubChartBoard(title: "Imported training", subtitle: "Minutes per day · same date axis") {
                Chart(report.points) { point in
                    BarMark(x: .value("Date", point.date), y: .value("Minutes", point.trainingMinutes)).foregroundStyle(HubTheme.plotPrimary)
                }.chartXScale(domain: domain).chartYAxisLabel("min")
                    .chartOverlay { proxy in inspector(proxy, report) }.frame(height: 145)
            }
        }
    }
    private func inspector(_ proxy: ChartProxy, _ report: RecoveryTrends) -> some View {
        ChartInspectionOverlay(proxy: proxy, reset: key) { (date: Date) in
            if let point = report.points.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }) {
                Text(point.date.formatted(date: .abbreviated, time: .omitted)).bold()
                Text("\(metric.title): \(formattedHealthValue(point.health, metric: metric))")
                Text("7-day mean: \(formattedHealthValue(point.rollingAverage, metric: metric)) (\(point.rollingDays)/7)")
                Text("Training: \(duration(point.trainingMinutes * 60)) · \(point.activities) recordings")
            }
        }
    }
    private struct HealthPoint: Identifiable { let date: Date; let value: Double; let segment: Int; var id: Date { date } }
    private func healthSegments(_ points: [RecoveryPoint]) -> [HealthPoint] {
        var segment = 0
        return points.compactMap { point in
            guard let value = point.health else { segment += 1; return nil }
            return HealthPoint(date: point.date, value: value, segment: segment)
        }
    }
    private func rollingSegment(_ point: RecoveryPoint, in points: [RecoveryPoint]) -> Int {
        points.prefix { $0.date <= point.date }.filter { $0.rollingAverage == nil }.count
    }
}
