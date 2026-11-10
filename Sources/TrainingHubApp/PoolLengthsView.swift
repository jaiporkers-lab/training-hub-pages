import SwiftUI
import TrainingHubCore

struct PoolLengthsView: View {
    let activity: Activity
    let store: ActivityStore
    @State private var swim: PoolSwim?
    @State private var loading = true
    @State private var error: String?
    @State private var includeRest = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pool lengths").font(.title3.bold())
            if loading {
                ProgressView("Reading lengths from the original FIT…")
            } else if let error {
                Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.secondary)
            } else if let swim {
                content(swim)
            } else {
                Label("No timed pool lengths in this recording.", systemImage: "figure.pool.swim")
                    .foregroundStyle(.secondary)
                Text("Open-water swims and some devices record laps or samples without individual pool lengths.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .task(id: activity.id) {
            loading = true
            error = nil
            defer { loading = false }
            do { swim = try await store.poolSwim(fileHash: activity.fileHash, sessionIndex: activity.sessionIndex) }
            catch { self.error = error.localizedDescription }
        }
    }

    private func content(_ swim: PoolSwim) -> some View {
        let active = swim.lengths.filter { $0.kind == .swim }
        let rests = swim.lengths.filter { $0.kind == .rest }
        let scores = active.compactMap(\.swolf)
        let average = scores.isEmpty ? nil : Double(scores.reduce(0, +)) / Double(scores.count)
        let pool = swim.lengthMeters.map { $0.formatted(.number.precision(.fractionLength(0...2))) + " m" } ?? "Unrecorded"
        let rows = includeRest ? swim.lengths : swim.lengths.filter { $0.kind != .rest }
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .leading), count: 7)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 24) {
                summary("Pool length", pool)
                summary("Swum lengths", String(active.count))
                summary("Rest intervals", String(rests.count))
                summary("Mean SWOLF", average?.formatted(.number.precision(.fractionLength(1))) ?? "—")
            }.frame(maxWidth: .infinity, alignment: .leading)
                .hubPanel(padding: 12)
            Toggle("Show rests", isOn: $includeRest).disabled(rests.isEmpty)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(["Start", "Stroke / type", "Timer", "Elapsed", "Strokes", "Pace / 100 m", "SWOLF"], id: \.self) {
                    Text($0).font(.caption.bold()).foregroundStyle(.secondary)
                }
                ForEach(rows) { length in
                    Text(duration(length.startOffset))
                    Text(length.kind == .swim ? length.stroke ?? length.kind.rawValue : length.kind.rawValue)
                    Text(reading(length.timer))
                    Text(reading(length.elapsed))
                    Text(length.strokes.map(String.init) ?? "—")
                    Text(reading(length.pacePer100Meters(poolLength: swim.lengthMeters)))
                    Text(length.swolf.map(String.init) ?? "—")
                }
            }.font(.callout).monospacedDigit()
            if rows.isEmpty { Text("No lengths to show with rests hidden.").foregroundStyle(.secondary) }
            Text("Pace uses the recorded pool length and timer. SWOLF adds rounded timer seconds and stroke count for each eligible swim length. Mean SWOLF uses \(scores.count) of \(active.count) swim lengths.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func summary(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline).monospacedDigit()
        }.accessibilityElement(children: .combine)
    }

    private func reading(_ value: Double?) -> String {
        value.map(duration) ?? "—"
    }
}
