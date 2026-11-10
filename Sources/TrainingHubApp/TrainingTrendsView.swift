import SwiftUI
import Charts
import TrainingHubCore

struct TrainingTrendsView: View {
    let activities: [Activity]
    @AppStorage("dashboard.trendWeeks") private var weeks = 4
    @State private var sport = "All sports"
    @State private var showDistance = false
    var body: some View {
        let report = TrainingTrends.make(activities: activities, weeks: weeks, sport: sport == "All sports" ? nil : sport, includeDemo: false)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 5) {
                    HubEyebrow("Training history", color: HubTheme.accent)
                    Text("Training trends").hubHeading()
                }
                HStack {
                    Picker("Period", selection: $weeks) {
                        Text("4 weeks").tag(4); Text("8 weeks").tag(8); Text("12 weeks").tag(12)
                    }.frame(width: 170)
                    Picker("Sport", selection: $sport) {
                        Text("All sports").tag("All sports")
                        ForEach(Set(activities.map(\.sport)).sorted(), id: \.self) { Text($0.capitalized).tag($0) }
                    }.frame(maxWidth: 220)
                    Picker("Measure", selection: $showDistance) { Text("Time").tag(false); Text("Distance").tag(true) }
                        .pickerStyle(.segmented).labelsHidden().frame(width: 170)
                }
                Text("\(report.start.formatted(date: .abbreviated, time: .omitted)) – \(report.end.formatted(date: .abbreviated, time: .omitted)) · Current week is partial")
                    .font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    SummaryCard(title: "ACTIVITIES", value: "\(report.current.activities)", symbol: "figure.mixed.cardio")
                    SummaryCard(title: "RECORDED DISTANCE", value: distance(report.current.meters), symbol: "location")
                    SummaryCard(title: "TRAINING TIME", value: duration(report.current.seconds), symbol: "clock")
                }
                Text("Based on imported recordings. Import all history before interpreting period changes.").font(.caption).foregroundStyle(.secondary)
                Text("Previous period: \(report.previous.activities) activities · \(distance(report.previous.meters)) · \(duration(report.previous.seconds))")
                    .font(.subheadline).monospacedDigit()
                HStack(spacing: 24) {
                    Text("Distance: \(change(report.current.meters, report.previous.meters))")
                    Text("Time: \(change(report.current.seconds, report.previous.seconds))")
                }.font(.caption).foregroundStyle(.secondary)
                WeeklyTrendChart(weeks: report.weeks, showDistance: showDistance)
                Text("Sport breakdown").font(.headline)
                ForEach(report.sports) { item in
                    HStack {
                        Text(item.sport.capitalized).frame(width: 110, alignment: .leading)
                        ProgressView(value: item.totals.seconds, total: max(1, report.current.seconds)).tint(HubTheme.accent)
                        Text(duration(item.totals.seconds)).monospacedDigit().frame(width: 80, alignment: .trailing)
                        Text(distance(item.totals.meters)).monospacedDigit().frame(width: 90, alignment: .trailing)
                    }.font(.callout)
                }
                if report.current.activities == 0 {
                    Text("No imported activities in this period. Choose a longer period, another sport, or import more history.").foregroundStyle(.secondary)
                }
                Text("Weeks start Monday. Previous period ends at the matching weekday and time. Counts treat a multisport file as one activity; sport totals use its individual legs, including transitions. Sessions are assigned to the parent activity's start date.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Time uses recorded timer duration, falling back to elapsed time for \(report.current.elapsedFallbacks) sessions. Distance sums known values; \(report.current.missingDistances) sessions lack distance. These are imported-library totals: an empty week can mean recordings have not been imported.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(.vertical, 8)
        }
    }
    private func change(_ value: Double, _ previous: Double) -> String {
        guard previous > 0 else { return value > 0 ? "No previous baseline" : "No recorded change" }
        return String(format: "%+.0f%%", (value - previous) / previous * 100)
    }
}

private struct WeeklyTrendChart: View {
    let weeks: [TrendWeek]
    let showDistance: Bool
    private func value(_ totals: TrendTotals) -> Double { showDistance ? totals.meters / 1_000 : totals.seconds / 3_600 }
    var body: some View {
        HubChartBoard(title: showDistance ? "Recorded distance" : "Training time", subtitle: "Weekly volume") {
            VStack(alignment: .leading, spacing: 8) {
                Chart(weeks) { week in
                    BarMark(x: .value("Week", week.start, unit: .weekOfYear), y: .value(showDistance ? "km" : "hours", value(week.current)))
                        .foregroundStyle(HubTheme.lime)
                    LineMark(x: .value("Week", week.start, unit: .weekOfYear), y: .value("Previous", value(week.previous)))
                        .foregroundStyle(HubTheme.comparison).lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 3]))
                        .symbol(.circle)
                }
                .chartXAxis { AxisMarks(values: weeks.map(\.start)) { _ in AxisGridLine(); AxisTick(); AxisValueLabel(format: .dateTime.day().month()) } }
                .chartYScale(domain: .automatic(includesZero: true))
                .chartYAxisLabel(showDistance ? "Distance (km)" : "Time (hours)")
                .chartOverlay { proxy in
                    ChartInspectionOverlay(proxy: proxy, reset: "\(showDistance)-\(weeks.map(\.start))") { (date: Date) in
                        if let week = weeks.last(where: { $0.start <= date }) {
                            Text("Week of \(week.start.formatted(date: .abbreviated, time: .omitted))").bold()
                            Text("\(week.current.activities) activities · \(distance(week.current.meters)) · \(duration(week.current.seconds))")
                            Text("Previous: \(distance(week.previous.meters)) · \(duration(week.previous.seconds))").foregroundStyle(HubTheme.comparison)
                        }
                    }
                }
                .frame(height: 220)
                .accessibilityLabel("Weekly training volume. Lime bars show the current period and the peach line shows the previous period.")
                Text("Lime bars · Current period     Peach line · Previous period")
                    .font(.caption).foregroundStyle(HubTheme.boardMuted)
            }
        }
    }
}
