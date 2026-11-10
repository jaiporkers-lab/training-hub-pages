import SwiftUI
import TrainingHubCore

struct ComparisonGraph: View {
    let store: ActivityStore
    let selected: Activity
    let baseline: Activity
    let selectedGroup: ActivityGroup
    let baselineGroup: ActivityGroup

    @State private var lhs: [Sample] = []
    @State private var rhs: [Sample] = []
    @State private var selectedIndex = SampleInspectionIndex()
    @State private var baselineIndex = SampleInspectionIndex()
    @State private var plot: [PlotPoint] = []
    @State private var metric: Metric = .heartRate
    @State private var distanceAxis = false
    @State private var smoothing = 0.0
    @State private var loading = true
    @State private var error: String?

    private var domain: ClosedRange<Double> {
        if distanceAxis { return 0...max(0.1, selectedIndex.maximumAxis ?? 0, baselineIndex.maximumAxis ?? 0) }
        return 0...(max(6, selected.elapsed, baseline.elapsed, lhs.last?.elapsed ?? 0, rhs.last?.elapsed ?? 0) / 60)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                Picker("Metric", selection: $metric) {
                    ForEach(Metric.allCases) { Text($0.rawValue).tag($0) }
                }.fixedSize()
                Picker("Align by", selection: $distanceAxis) {
                    Text("Elapsed time").tag(false)
                    Text("Recorded distance").tag(true)
                }.fixedSize()
                Picker("Smoothing", selection: $smoothing) {
                    Text("Raw").tag(0.0)
                    Text("5 sec").tag(5.0)
                    Text("15 sec").tag(15.0)
                    Text("30 sec").tag(30.0)
                }.fixedSize()
            }.disabled(loading || error != nil)
            if loading {
                ProgressView("Reading both recordings…").padding(.vertical, 16)
            } else if let error {
                Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.secondary)
            } else if plot.isEmpty {
                ContentUnavailableView("No comparable samples for this view", systemImage: "chart.xyaxis.line",
                    description: Text("Choose another metric or alignment. Both recordings lack usable points for this selection."))
                    .frame(height: 130)
            } else {
                ActivityPlot(activity: selected, comparisonActivity: baseline, group: selectedGroup, comparisonGroup: baselineGroup,
                             samples: lhs, comparison: rhs, sampleIndex: selectedIndex, comparisonIndex: baselineIndex,
                             plot: plot, metric: metric, distanceAxis: distanceAxis, smoothing: smoothing, domain: domain,
                             chartUnit: metric == .pace && selected.sport == "swimming" ? "min/100m" : metric.unit, secondaryLabel: "Baseline")
                if !plot.contains(where: { $0.series == "Selected" }) {
                    Text("The selected activity has no usable points for this metric and alignment.").font(.caption).foregroundStyle(.secondary)
                }
                if !plot.contains(where: { $0.series == "Baseline" }) {
                    Text("The baseline has no usable points for this metric and alignment.").font(.caption).foregroundStyle(.secondary)
                }
                Text("Hover to inspect both recordings at the same elapsed time or distance. Dashed markers show each race’s leg boundaries.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .task {
            defer { loading = false }
            do {
                let left = try await store.samples(for: selected.id)
                try Task.checkCancellation()
                let right = try await store.samples(for: baseline.id)
                try Task.checkCancellation()
                lhs = left
                rhs = right
                let preferred: Metric = ["swimming", "running"].contains(selected.sport) ? .pace : .heartRate
                metric = ActivityGraph.preferredMetric(preferred, selected: left, baseline: right)
                rebuildIndex()
                rebuildPlot()
            } catch is CancellationError {
                return
            } catch {
                self.error = error.localizedDescription
            }
        }
        .onChange(of: distanceAxis) { rebuildIndex(); rebuildPlot() }
        .onChange(of: metric) { rebuildPlot() }
        .onChange(of: smoothing) { rebuildPlot() }
    }

    private func rebuildIndex() {
        selectedIndex = SampleInspectionIndex(samples: lhs, distanceAxis: distanceAxis)
        baselineIndex = SampleInspectionIndex(samples: rhs, distanceAxis: distanceAxis)
    }

    private func rebuildPlot() {
        plot = activityPlotPoints(lhs, activity: selected, group: selectedGroup, metric: metric, distanceAxis: distanceAxis,
                                  smoothing: smoothing, series: "Selected", prefix: "a") +
               activityPlotPoints(rhs, activity: baseline, group: baselineGroup, metric: metric, distanceAxis: distanceAxis,
                                  smoothing: smoothing, series: "Baseline", prefix: "b")
    }
}
