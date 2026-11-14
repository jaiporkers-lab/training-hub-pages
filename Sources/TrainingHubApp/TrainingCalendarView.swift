import SwiftUI
import AppKit
import TrainingHubCore

struct TrainingCalendarView: View {
    let groups: [ActivityGroup]
    let openActivity: (String) -> Void
    @AppStorage("calendar.plans") private var plansJSON = "[]"
    @State private var weekOffset = 0
    @State private var editing: TrainingPlan?
    @State private var error: String?
    @State private var watchHelp = false
    @State private var undoJSON: String?
    private var calendar: Calendar { var value = Calendar.current; value.firstWeekday = 2; return value }
    private var weekStart: Date { calendar.date(byAdding: .weekOfYear, value: weekOffset, to: calendar.dateInterval(of: .weekOfYear, for: Date())!.start)! }
    private var days: [Date] { (0..<7).map { calendar.date(byAdding: .day, value: $0, to: weekStart)! } }
    private var plans: [TrainingPlan] { (try? TrainingPlan.decode(plansJSON)) ?? [] }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HubEyebrow("Plan & review", color: HubTheme.accent)
                        Text("Training calendar").hubHeading()
                    }
                    Spacer()
                    Button { watchHelp = true } label: { Label("Watch calendar", systemImage: "applewatch") }
                        .popover(isPresented: $watchHelp) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Garmin watch calendar").font(.headline)
                                Text("GarHub’s Personal API connection can read Garmin data, but cannot create or schedule workouts. Automatic watch-calendar publishing requires Garmin’s separate Training API with Enterprise access.")
                                Text("For now, use a plan’s context menu to copy its details. Create and schedule the workout in Garmin Connect, then sync your compatible watch. Local edits here will not change your watch calendar.")
                                Link("How to schedule a workout in Garmin Connect", destination: URL(string: "https://support.garmin.com/en-US/?faq=XRcMvEtKdf7yBf8My9jua6")!)
                                Link("Open Garmin Connect", destination: URL(string: "https://connect.garmin.com/")!)
                                Link("Garmin Training API access", destination: URL(string: "https://developer.garmin.com/gc-developer-program/enterprise/training-api/")!)
                            }.font(.callout).padding(20).frame(width: 390)
                        }
                    Button { add(on: Date()) } label: { Label("New plan", systemImage: "plus") }.buttonStyle(.borderedProminent)
                }
                HStack {
                    Button { weekOffset -= 1 } label: { Image(systemName: "chevron.left") }.help("Previous week")
                    Text("\(weekStart.formatted(.dateTime.day().month(.abbreviated))) – \(days.last!.formatted(.dateTime.day().month(.abbreviated).year()))").font(.headline).monospacedDigit()
                    Button { weekOffset += 1 } label: { Image(systemName: "chevron.right") }.help("Next week")
                    Button("This week") { weekOffset = 0 }
                    Spacer()
                    if undoJSON != nil { Button("Undo last change") { if let previous = undoJSON { plansJSON = previous; undoJSON = nil } } }
                }
                Text("Drag a planned session or race onto another day to reschedule. Select a completed recording to open its analysis. Plans stay on this Mac and are included in library backups.")
                    .font(.callout).foregroundStyle(.secondary)
                Label("Plans are local · Watch-calendar sync is unavailable with a Personal API key", systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
                if let error { Text(error).foregroundStyle(.red) }
                if (try? TrainingPlan.decode(plansJSON)) == nil { Text("Saved plans could not be read. Restore a library backup to recover them; new changes are disabled.").foregroundStyle(.red) }
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(days, id: \.self) { day in dayColumn(day) }
                    }.padding(.vertical, 3)
                }
                let planned = plans.filter { $0.date >= weekStart && $0.date < calendar.date(byAdding: .day, value: 7, to: weekStart)! }
                let completed = groups.filter { $0.summary.start >= weekStart && $0.summary.start < calendar.date(byAdding: .day, value: 7, to: weekStart)! }
                HStack(spacing: 18) {
                    SummaryCard(title: "PLANNED", value: "\(planned.count) · \(duration(planned.reduce(0) { $0 + $1.minutes * 60 }))", symbol: "calendar")
                    SummaryCard(title: "COMPLETED", value: "\(completed.count) · \(duration(completed.reduce(0) { $0 + ($1.summary.timer ?? $1.summary.elapsed) }))", symbol: "checkmark.circle")
                }
                Text("Completed recordings and plans remain separate. This calendar does not upload workouts to a device or automatically mark plans completed.").font(.caption).foregroundStyle(.secondary)
            }.padding(.vertical, 8)
        }
        .sheet(item: $editing) { plan in
            PlanEditor(plan: plan) { updated in
                save(plans.filter { $0.id != updated.id } + [updated]); editing = nil
            }
        }
    }
    private func dayColumn(_ day: Date) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(day.formatted(.dateTime.weekday(.abbreviated))).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(day.formatted(.dateTime.day().month(.abbreviated))).font(.headline)
            }.foregroundStyle(calendar.isDateInToday(day) ? HubTheme.accent : HubTheme.ink)
            Divider()
            ForEach(plans.filter { calendar.isDate($0.date, inSameDayAs: day) }) { plan in
                Button { editing = plan } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Label(plan.kind.rawValue, systemImage: plan.kind == .race ? "flag.checkered" : sportSymbol(plan.sport)).font(.caption.weight(.semibold)).foregroundStyle(HubTheme.accent)
                        Text(plan.title).font(.callout.weight(.semibold))
                        Text("\(plan.date.formatted(date: .omitted, time: .shortened)) · \(Int(plan.minutes)) min").font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
                        .background(HubTheme.accentWash, in: RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain).draggable(plan.id)
                    .contextMenu {
                        Button("Edit") { editing = plan }
                        Button("Copy details for Garmin Connect") {
                            let text = "\(plan.title)\n\(plan.kind.rawValue) · \(plan.sport)\n\(plan.date.formatted(date: .complete, time: .shortened))\nPlanned duration: \(Int(plan.minutes)) minutes\nCreate and schedule this workout in Garmin Connect, then sync your watch."
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(text, forType: .string)
                        }
                        Button("Delete plan", role: .destructive) { save(plans.filter { $0.id != plan.id }) }
                    }
            }
            ForEach(groups.filter { calendar.isDate($0.summary.start, inSameDayAs: day) }) { group in
                Button { openActivity(group.id) } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Label("Completed", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(HubTheme.accent)
                        Text(group.summary.title).font(.callout.weight(.semibold)).lineLimit(3)
                        Text("\(duration(group.summary.timer ?? group.summary.elapsed)) · \(distance(group.summary.distance))").font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
                        .background(HubTheme.background, in: RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain)
            }
            Button { add(on: day) } label: { Label("Add plan", systemImage: "plus") }.font(.caption).buttonStyle(.link)
            Spacer(minLength: 30)
        }.frame(width: 155, alignment: .topLeading).frame(minHeight: 330).padding(12)
            .background(HubTheme.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(HubTheme.line))
            .dropDestination(for: String.self) { ids, _ in
                guard let id = ids.first, let plan = plans.first(where: { $0.id == id }), ids.count == 1 else { return false }
                save(plans.filter { $0.id != id } + [plan.moved(to: day, calendar: calendar)])
                return true
            }
    }
    private func add(on day: Date) {
        editing = TrainingPlan(title: "", date: calendar.date(bySettingHour: 7, minute: 0, second: 0, of: day) ?? day,
                               sport: "running", minutes: 45, kind: .workout)
    }
    private func save(_ next: [TrainingPlan]) {
        guard (try? TrainingPlan.decode(plansJSON)) != nil else { return }
        do { let json = try TrainingPlan.encode(next); undoJSON = plansJSON; plansJSON = json; error = nil }
        catch { self.error = error.localizedDescription }
    }
}

private struct PlanEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var plan: TrainingPlan
    let save: (TrainingPlan) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Planned session").font(.title2.bold())
            TextField("Session title", text: $plan.title).textFieldStyle(.roundedBorder)
            Picker("Type", selection: $plan.kind) { ForEach(TrainingPlan.Kind.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
            Picker("Sport", selection: $plan.sport) {
                ForEach(["running", "cycling", "swimming", "walking", "hiking", "strengthTraining", "multisport", "other"], id: \.self) { Text($0 == "strengthTraining" ? "Strength" : $0.capitalized).tag($0) }
            }
            DatePicker("When", selection: $plan.date)
            HStack { Text("Planned minutes"); TextField("Minutes", value: $plan.minutes, format: .number).textFieldStyle(.roundedBorder).frame(width: 100) }
            HStack { Spacer(); Button("Cancel") { dismiss() }; Button("Save plan") { plan.title = plan.title.trimmingCharacters(in: .whitespacesAndNewlines); save(plan) }.buttonStyle(.borderedProminent).disabled(plan.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || plan.title.count > 120 || !plan.minutes.isFinite || !(0...10_080).contains(plan.minutes)) }
        }.padding(24).frame(width: 440)
    }
}
