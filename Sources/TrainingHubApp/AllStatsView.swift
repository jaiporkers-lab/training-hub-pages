import SwiftUI
import TrainingHubCore

struct AllStatsView: View {
    let activity: Activity
    let group: ActivityGroup?
    let store: ActivityStore
    @State private var sessions: [RecordedSessionStats] = []
    @State private var search = ""
    @State private var error: String?
    @State private var loading = true
    @State private var showRaw = false
    var body: some View {
        LazyVStack(alignment: .leading, spacing: 16) {
            Text("All stats").font(.title2.bold())
            TextField("Find a recorded stat", text: $search).textFieldStyle(.roundedBorder).frame(maxWidth: 400)
            Toggle("Show original field names and timestamp values", isOn: $showRaw).font(.caption)
            Text("Statistics recorded in the original activity file, grouped by leg. Missing fields stay unavailable.")
                .font(.caption).foregroundStyle(.secondary)
            DisclosureGroup("About recorded fields") {
                Text("Values and units come from the FIT SDK, including recognised developer fields. Timestamps are displayed in your Mac's time zone; enable original values to see FIT epoch seconds. Arrays retain recorded order and positions retain their recorded units. The recorded summary timestamp is not necessarily the activity finish.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if activity.id.hasPrefix(ActivityGroup.idPrefix) {
                Text("Whole activity · locally combined").font(.headline)
                LabeledContent("Recorded leg distance", value: distance(activity.distance))
                LabeledContent("Timer sum", value: activity.timer.map(duration) ?? "Not recorded")
                LabeledContent("Elapsed span", value: duration(activity.elapsed))
                Text("The original fields below belong to each leg. Sensor averages and proprietary scores are not added together.").font(.caption).foregroundStyle(.secondary)
            }
            if loading { ProgressView("Reading original session fields…") }
            if let error { Text(error).foregroundStyle(.red) }
            ForEach(sessions.filter { activity.sessionIndex < 0 || $0.id == activity.sessionIndex }) { session in
                let leg = group?.sessions.first { $0.sessionIndex == session.id }
                let rows = session.stats.filter { search.isEmpty || readableFieldName($0.field).localizedCaseInsensitiveContains(search) || $0.field.localizedCaseInsensitiveContains(search) || $0.unit.localizedCaseInsensitiveContains(search) }
                if !rows.isEmpty {
                    Text(leg.map { group?.legName($0) ?? $0.displaySport } ?? activity.displaySport).font(.headline)
                    Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 9) {
                        GridRow { Text("Recorded field").bold(); Text("Value").bold(); Text("Unit").bold() }
                        ForEach(rows) { stat in
                            GridRow {
                                Text(showRaw ? stat.field : readableFieldName(stat.field)).foregroundStyle(.secondary)
                                Text(displayValue(stat)).monospacedDigit().textSelection(.enabled)
                                Text(!showRaw && ["fit:2", "fit:253"].contains(stat.id) ? "Local time" : stat.unit).foregroundStyle(.secondary)
                            }
                        }
                    }.font(.callout).frame(maxWidth: .infinity, alignment: .leading).hubPanel(padding: 14)
                }
            }
            if !loading && !search.isEmpty && !sessions.contains(where: { session in (activity.sessionIndex < 0 || session.id == activity.sessionIndex) && session.stats.contains { readableFieldName($0.field).localizedCaseInsensitiveContains(search) || $0.field.localizedCaseInsensitiveContains(search) || $0.unit.localizedCaseInsensitiveContains(search) } }) {
                Text("No matching stats. Try a field name such as heart rate, distance or power.").foregroundStyle(.secondary)
            }
            if !loading && sessions.allSatisfy({ $0.stats.isEmpty }) && error == nil { Text("No supported session fields were recorded.").foregroundStyle(.secondary) }
        }
        .task(id: activity.fileHash) {
            loading = true
            defer { loading = false }
            do { sessions = try await store.recordedStats(fileHash: activity.fileHash) }
            catch { self.error = error.localizedDescription }
        }
    }
    private func displayValue(_ stat: RecordedStat) -> String {
        guard !showRaw, ["fit:2", "fit:253"].contains(stat.id), let seconds = Double(stat.value),
              let epoch = ISO8601DateFormatter().date(from: "1989-12-31T00:00:00Z") else { return stat.value }
        return epoch.addingTimeInterval(seconds).formatted(date: .abbreviated, time: .standard)
    }
}
