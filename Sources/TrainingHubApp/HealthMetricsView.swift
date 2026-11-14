import SwiftUI
import Charts
import TrainingHubCore

struct HealthMetricsView: View {
    @ObservedObject var model: HubModel
    @State private var metricID = "rhr"
    @State private var days = 14
    private var metric: HealthMetric { HealthMetric.all.first { $0.id == metricID }! }
    var body: some View {
        let comparison = HealthAnalysis.compare(model.health.days, metric: metric, days: days)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    HubEyebrow("Recovery", color: HubTheme.accent)
                    Text("Health & recovery").hubHeading()
                }
                HStack {
                    Picker("Metric", selection: $metricID) {
                        ForEach(HealthMetric.all) { Text($0.title).tag($0.id) }
                    }.frame(maxWidth: 340)
                    Picker("Compare", selection: $days) {
                        Text("7 days").tag(7); Text("14 days").tag(14); Text("30 days").tag(30)
                    }.frame(width: 160)
                    Button("Sync health") { model.syncHealth(days: days) }
                        .disabled(!model.keyAvailable || model.busy || model.syncing || model.healthSyncing || model.testingConnection)
                    if model.healthSyncing { ProgressView().controlSize(.small); Button("Cancel") { model.cancelSync() } }
                }
                Text(model.healthStatus).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                HStack(spacing: 12) {
                    SummaryCard(title: "CURRENT DAILY AVERAGE", value: formatted(comparison.current), symbol: "heart")
                    SummaryCard(title: "PREVIOUS DAILY AVERAGE", value: formatted(comparison.previous), symbol: "clock.arrow.circlepath")
                }
                if let current = comparison.current, let previous = comparison.previous {
                    Text(String(format: "Change: %+.2f %@", current - previous, metric.unit)).font(.headline).monospacedDigit()
                }
                Text("Recorded coverage: \(comparison.currentCount)/\(days) current days · \(comparison.previousCount)/\(days) previous days. Today is excluded from both periods.")
                    .font(.caption).foregroundStyle(.secondary)
                HealthDailyChart(records: model.health.days, metric: metric, days: days).id("\(metricID)-\(days)")
                if comparison.currentCount + comparison.previousCount == 0 {
                    ContentUnavailableView("No recorded \(metric.title.lowercased())", systemImage: "heart.text.square", description: Text("Sync health, or choose another metric. Availability depends on your device, recordings and Garmin API access."))
                        .frame(height: 140)
                }
                Text("Source: Garmin \(metric.source.title). These are recorded daily summaries, not diagnoses or a readiness prescription. Missing days and negative unavailable sentinels are omitted; they are never treated as zero. Sleep is associated with Garmin's calendar date; weight uses the latest measurement on a recorded day.")
                    .font(.caption).foregroundStyle(.secondary)
                if ["stress", "sleepScore"].contains(metricID) { Text("Garmin scale: 0–100 points.").font(.caption).foregroundStyle(.secondary) }
                if metricID.hasPrefix("bb") { Text("Garmin Body Battery scale: 5–100 points.").font(.caption).foregroundStyle(.secondary) }
                if metricID == "rhr" { Text("Garmin may supply the day's minimum when a resting value is unavailable.").font(.caption).foregroundStyle(.secondary) }
                if let updated = model.health.updated { Text("Latest local update: \(updated.formatted())").font(.caption).foregroundStyle(.secondary) }
                Text("Sync fetches only the two comparison periods in batches of at most 31 days. Measurements stay in your local SQLite library and its backups. This app makes no AI calls.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(.vertical, 8)
        }
    }
    private func formatted(_ value: Double?) -> String { formattedHealthValue(value, metric: metric) }
}

private struct HealthDailyChart: View {
    struct Point: Identifiable {
        let date: Date; let value: Double; let segment: Int
        var id: Date { date }
    }
    let records: [HealthDay]
    let metric: HealthMetric
    let days: Int
    private let points: [Point]
    init(records: [HealthDay], metric: HealthMetric, days: Int) {
        self.records = records; self.metric = metric; self.days = days
        self.points = Self.prepare(records: records, metric: metric, days: days)
    }
    private static func prepare(records: [HealthDay], metric: HealthMetric, days: Int) -> [Point] {
        let calendar = Calendar.current, today = Calendar.current.startOfDay(for: Date())
        let start = calendar.date(byAdding: .day, value: -2 * days, to: today)!
        let values = records.filter { $0.source == metric.source }.compactMap { record -> (Date, Double)? in
            guard let date = HealthAnalysis.date(record.day), date >= start, date < today, let value = record.values[metric.id] else { return nil }
            return (date, value)
        }.sorted { $0.0 < $1.0 }
        var segment = 0, previous: Date?
        return values.map { date, value in
            if let previous, (calendar.dateComponents([.day], from: previous, to: date).day ?? 0) > 1 { segment += 1 }
            previous = date
            return Point(date: date, value: value, segment: segment)
        }
    }
    var body: some View {
        let data = points
        HubChartBoard(title: metric.title, subtitle: "Daily measurements") {
            Chart {
                ForEach(data) { point in
                    LineMark(x: .value("Date", point.date), y: .value(metric.unit, point.value), series: .value("Recorded span", point.segment)).foregroundStyle(HubTheme.plotPrimary)
                    PointMark(x: .value("Date", point.date), y: .value(metric.unit, point.value)).foregroundStyle(HubTheme.plotPrimary)
                }
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .chartYAxisLabel(metric.unit)
            .chartOverlay { proxy in
                ChartInspectionOverlay(proxy: proxy, reset: "\(metric.id)-\(days)") { (date: Date) in
                    if let point = data.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }), abs(point.date.timeIntervalSince(date)) < 43_200 {
                        Text(point.date.formatted(date: .abbreviated, time: .omitted)).bold()
                        Text("\(metric.title): \(formattedHealthValue(point.value, metric: metric))")
                    } else {
                        Text(date.formatted(date: .abbreviated, time: .omitted)).bold()
                        Text("Not recorded here")
                    }
                }
            }
            .frame(height: 220)
            .accessibilityLabel("\(metric.title) over the current and previous periods")
        }
    }
}
