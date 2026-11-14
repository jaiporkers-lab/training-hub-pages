import SwiftUI
import TrainingHubCore

struct TrainingProgressView: View {
    let activities: [Activity]
    let store: ActivityStore?
    let openActivity: (String) -> Void
    @AppStorage("dashboard.home.weeklyHours") private var weeklyHours = 0.0
    @AppStorage("dashboard.goals.weeklyKilometers") private var weeklyKM = 0.0
    @AppStorage("dashboard.goals.milestoneKilometers") private var milestoneKM = 1_000.0
    @State private var sport = "running"
    @State private var records: [PersonalBest] = []
    @State private var scanning = false
    @State private var scanRequested = 0
    @State private var progress = ""
    @State private var error: String?
    var body: some View {
        let week = TrainingTrends.make(activities: activities, weeks: 1)
        let kilometers = activities.filter { !$0.isDemo && $0.sessionIndex >= 0 }.reduce(0) { $0 + max(0, $1.distance ?? 0) } / 1_000
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HubEyebrow("Your targets", color: HubTheme.accent)
                Text("Goals & recorded bests").hubHeading()
                HStack(alignment: .top, spacing: 16) {
                    goal("Weekly time", current: week.current.seconds / 3_600, target: $weeklyHours, unit: "hours", maximum: 168)
                    goal("Weekly distance", current: week.current.meters / 1_000, target: $weeklyKM, unit: "km", maximum: 10_000)
                    goal("Distance milestone", current: kilometers, target: $milestoneKM, unit: "km", maximum: 1_000_000)
                }
                Text("Weekly goals include all imported sports from Monday to now. Milestones total recorded session distances in this library. Missing distances add no distance; \(week.current.missingDistances) session(s) have no distance this week. Zero turns a target off.").font(.caption).foregroundStyle(.secondary)
                Divider()
                HStack {
                    Text("Personal records").font(.title2.bold())
                    Spacer()
                    Picker("Sport", selection: $sport) { Text("Running distance").tag("running"); Text("Cycling power").tag("cycling") }.frame(width: 260).disabled(scanning)
                    Button(scanning ? "Cancel" : "Calculate recorded bests") {
                        if scanning { scanRequested = 0 } else { scanRequested += 1 }
                    }.disabled(store == nil)
                }
                Text("Scan the local library for continuous distance or power efforts. Results are calculated from imported recordings, including individual multisport legs. They may differ from device or Garmin personal records.").font(.callout).foregroundStyle(.secondary)
                if scanning { HStack { ProgressView().controlSize(.small); Text(progress).font(.caption) } }
                if let error { Text(error).foregroundStyle(.red) }
                if records.isEmpty && !scanning { Text("Select a sport and calculate to see the best efforts supported by your recordings.").foregroundStyle(.secondary).padding(.vertical) }
                ForEach(records) { record in
                    Button { openActivity(record.activityID) } label: {
                        HStack(spacing: 20) {
                            Text(sport == "cycling" ? duration(record.target) : distance(record.target)).font(.headline).frame(width: 100, alignment: .leading)
                            Text(sport == "cycling" ? number(record.value, unit: "W") : duration(record.value)).font(.title3.bold()).monospacedDigit().frame(width: 110, alignment: .leading)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(record.title).lineLimit(1)
                                Text("\(record.date.formatted(date: .abbreviated, time: .omitted)) · from \(duration(record.start))").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(); Image(systemName: "arrow.up.right").foregroundStyle(HubTheme.accent)
                        }.contentShape(Rectangle()).hubPanel(padding: 14)
                    }.buttonStyle(.plain)
                }
                Text("Gaps over 30 seconds, missing sensor readings and distance resets break an effort. Zero power is valid. A pause inside a distance effort counts toward elapsed time. Recalculate after importing more activities.").font(.caption).foregroundStyle(.secondary)
            }.padding(.vertical, 8)
        }
        .onChange(of: sport) { records = []; scanRequested = 0; error = nil }
        .task(id: scanRequested) {
            guard scanRequested > 0, let store else { scanning = false; return }
            scanning = true; error = nil; records = []; progress = "Reading recordings…"
            defer { if !Task.isCancelled { scanning = false } }
            do {
                let result = try await store.personalBests(sport: sport, activities: activities) { done, total in
                    await MainActor.run { progress = "\(done) of \(total) sessions" }
                }
                guard !Task.isCancelled else { return }
                records = result
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
    private func goal(_ title: String, current: Double, target: Binding<Double>, unit: String, maximum: Double) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            Text(String(format: "%.1f %@", current, unit)).font(.title2.bold()).monospacedDigit()
            if target.wrappedValue > 0 {
                ProgressView(value: min(current, target.wrappedValue), total: target.wrappedValue).tint(HubTheme.accent)
                Text(current >= target.wrappedValue ? "Target reached" : String(format: "%.1f %@ to go", target.wrappedValue - current, unit)).font(.caption).foregroundStyle(.secondary)
            }
            HStack { Text("Target").font(.caption); TextField("Target", value: target, format: .number).frame(maxWidth: 95).textFieldStyle(.roundedBorder); Text(unit).font(.caption) }
                .onChange(of: target.wrappedValue) { target.wrappedValue = target.wrappedValue.isFinite ? min(maximum, max(0, target.wrappedValue)) : 0 }
        }.frame(maxWidth: .infinity, alignment: .leading).hubPanel()
    }
}
