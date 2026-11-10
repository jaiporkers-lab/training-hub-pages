import SwiftUI
import Charts
import TrainingHubCore

struct PlotPoint: Identifiable {
    let id: String
    let x: Double
    let y: Double
    let series: String
    let segment: String
}

func activityPlotPoints(_ samples: [Sample], activity: Activity, group: ActivityGroup?, metric: Metric,
                        distanceAxis: Bool, smoothing: Double, series: String, prefix: String) -> [PlotPoint] {
    let breaks = activity.id.hasPrefix(ActivityGroup.idPrefix)
        ? group?.sessions.dropFirst().map { $0.start.timeIntervalSince(activity.start) } ?? []
        : []
    let points = ActivityGraph.points(samples, metric: metric, distanceAxis: distanceAxis, smoothing: smoothing,
                                      breaks: breaks, swimPace: activity.sport == "swimming")
    return ActivityGraph.displayPoints(points).map { point in
        PlotPoint(id: "\(prefix)-\(point.id)", x: point.x, y: point.y,
                  series: series, segment: "\(prefix)-\(point.segment)")
    }
}

// Cursor changes stay here: smoothing, grouping and interval statistics in the
// parent are not rebuilt on every inspection movement.
struct ActivityPlot: View {
    let activity: Activity
    let comparisonActivity: Activity?
    let group: ActivityGroup?
    let comparisonGroup: ActivityGroup?
    let samples: [Sample]
    let comparison: [Sample]
    let sampleIndex: SampleInspectionIndex
    let comparisonIndex: SampleInspectionIndex
    let plot: [PlotPoint]
    let metric: Metric
    let distanceAxis: Bool
    let smoothing: Double
    let domain: ClosedRange<Double>
    let chartUnit: String
    var secondaryLabel = "Comparison"
    private var wholeRace: Bool { activity.id.hasPrefix(ActivityGroup.idPrefix) }
    private var reset: String { "\(metric.id)-\(distanceAxis)-\(domain)-\(smoothing)-\(comparisonActivity?.id ?? "")" }
    var body: some View {
        HubChartBoard(title: metric.rawValue, subtitle: distanceAxis ? "By recorded distance" : "By elapsed time") {
            Chart {
                if wholeRace, let group {
                    ForEach(Array(group.sessions.indices.dropFirst()), id: \.self) { index in
                        if let position = boundary(index, group: group, activity: activity) {
                            RuleMark(x: .value("Selected leg boundary", position))
                                .foregroundStyle(HubTheme.lime.opacity(0.43)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        }
                    }
                }
                if let comparisonActivity, comparisonActivity.id.hasPrefix(ActivityGroup.idPrefix), let comparisonGroup {
                    ForEach(Array(comparisonGroup.sessions.indices.dropFirst()), id: \.self) { index in
                        if let position = boundary(index, group: comparisonGroup, activity: comparisonActivity) {
                            RuleMark(x: .value("Baseline leg boundary", position))
                                .foregroundStyle(HubTheme.comparison.opacity(0.47)).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                        }
                    }
                }
                ForEach(plot) { point in
                    LineMark(x: .value(distanceAxis ? "km" : "min", point.x), y: .value(chartUnit, point.y), series: .value("Segment", point.segment))
                        .foregroundStyle(by: .value("Activity", point.series)).lineStyle(StrokeStyle(lineWidth: 1.8))
                }
            }
            .chartForegroundStyleScale(["Selected": HubTheme.lime, secondaryLabel: HubTheme.comparison])
            .chartLegend(comparison.isEmpty ? .hidden : .visible)
            .chartXScale(domain: domain)
            .chartYScale(domain: .automatic(includesZero: metric == .speed || metric == .power))
            .chartXAxisLabel(distanceAxis ? "Distance (km)" : "Elapsed time (min)")
            .chartYAxisLabel(chartUnit)
            .chartYAxis {
                if metric == .pace {
                    AxisMarks { value in
                        AxisGridLine().foregroundStyle(HubTheme.boardLine); AxisTick().foregroundStyle(HubTheme.boardLine)
                        AxisValueLabel { if let value = value.as(Double.self) { Text(paceMinutes(value)) } }
                    }
                } else {
                    AxisMarks {
                        AxisGridLine().foregroundStyle(HubTheme.boardLine)
                        AxisTick().foregroundStyle(HubTheme.boardLine)
                        AxisValueLabel()
                    }
                }
            }
            .chartOverlay { proxy in
                ChartInspectionOverlay(proxy: proxy, reset: reset) { (position: Double) in
                    Text(String(format: "%.2f %@", position, distanceAxis ? "km" : "min")).bold()
                    if let label = legLabel(activity: activity, group: group, axis: position) { Text(label).fontWeight(.semibold).foregroundStyle(HubTheme.lime) }
                    let primary = nearest(samples, index: sampleIndex, position, activity: activity)
                    if comparisonActivity == nil {
                        Text(smoothing > 0 ? "Raw: \(primary)" : primary)
                            .fontWeight(.semibold).monospacedDigit()
                    } else {
                        Text("Selected\(smoothing > 0 ? " (raw)" : ""): \(primary)")
                    }
                    if let comparisonActivity {
                        if let label = legLabel(activity: comparisonActivity, group: comparisonGroup, axis: position) { Text("\(secondaryLabel) · \(label)").foregroundStyle(HubTheme.comparison) }
                        Text("\(secondaryLabel)\(smoothing > 0 ? " (raw)" : ""): \(nearest(comparison, index: comparisonIndex, position, activity: comparisonActivity))")
                    }
                }
            }
            .frame(height: 242)
            .accessibilityLabel("\(metric.rawValue) by \(distanceAxis ? "distance" : "elapsed time")")
        }
    }

    private func legLabel(activity: Activity, group: ActivityGroup?, axis: Double) -> String? {
        guard let group, group.isMultisport else { return nil }
        if !activity.id.hasPrefix(ActivityGroup.idPrefix) { return group.legName(activity) }
        guard let leg = group.leg(at: axis * (distanceAxis ? 1_000 : 60), distance: distanceAxis) else {
            return distanceAxis ? "Leg unavailable at this distance" : "Between legs"
        }
        return group.legName(leg)
    }
    private func boundary(_ index: Int, group: ActivityGroup, activity: Activity) -> Double? {
        if !distanceAxis { return group.sessions[index].start.timeIntervalSince(activity.start) / 60 }
        let distances = group.sessions.prefix(index).compactMap(\.distance)
        return distances.count == index ? distances.reduce(0, +) / 1_000 : nil
    }
    private func nearest(_ data: [Sample], index: SampleInspectionIndex, _ axis: Double, activity: Activity) -> String {
        guard let ordinal = index.nearest(to: axis, tolerance: distanceAxis ? 0.05 : 0.5),
              let value = metric.value(data[ordinal]), value.isFinite else { return "Not recorded here" }
        if metric == .pace { return "\(paceMinutes(activity.sport == "swimming" ? value / 10 : value)) \(activity.sport == "swimming" ? "min/100m" : "min/km")" }
        return String(format: "%.1f %@", value, chartUnit)
    }
}
