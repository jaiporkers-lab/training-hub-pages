import SwiftUI
import TrainingHubCore

struct HomeView: View {
    @ObservedObject var model: HubModel
    let navigate: (String) -> Void
    let openActivity: (String) -> Void
    @AppStorage("dashboard.home.training") private var showTraining = true
    @AppStorage("dashboard.home.health") private var showHealth = true
    @AppStorage("dashboard.home.recent") private var showRecent = true
    @AppStorage("dashboard.home.goal") private var showGoal = true
    @AppStorage("dashboard.home.weeklyHours") private var weeklyHours = 0.0
    var body: some View {
        let week = TrainingTrends.make(activities: model.activities, weeks: 1)
        let recent = Array(model.groups.prefix(5))
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .center) {
                    HubEyebrow(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    Spacer()
                    Menu {
                        Toggle("This week", isOn: $showTraining)
                        Toggle("Health snapshot", isOn: $showHealth)
                        Toggle("Recent activities", isOn: $showRecent)
                        Toggle("Weekly goal", isOn: $showGoal)
                    } label: { Label("Customise Home", systemImage: "slider.horizontal.3") }
                }
                if showRecent, let featured = recent.first {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 24) {
                            introduction.frame(minWidth: 248, maxWidth: .infinity, alignment: .leading)
                            latestActivity(featured).frame(minWidth: 310, maxWidth: .infinity)
                        }
                        VStack(alignment: .leading, spacing: 18) {
                            introduction
                            latestActivity(featured)
                        }
                    }
                } else {
                    introduction
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), alignment: .top)], alignment: .leading, spacing: 16) {
                    if showTraining {
                        card("This week", symbol: "chart.bar.fill") {
                            Text(duration(week.current.seconds)).font(.system(size: 30, weight: .semibold)).monospacedDigit()
                            Text("\(week.current.activities) activities · \(distance(week.current.meters))").font(.headline)
                            Text("Same point last week: \(duration(week.previous.seconds)) · \(distance(week.previous.meters))")
                                .font(.caption).foregroundStyle(.secondary)
                            Button("Explore training trends") { navigate("Trends") }.buttonStyle(.link)
                            Text("Imported activities · Monday start · Current week in progress").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    if showGoal {
                        card("Weekly time goal", symbol: "target") {
                            if weeklyHours > 0 {
                                Text(String(format: "%.1f / %.1f hours", week.current.seconds / 3_600, weeklyHours)).font(.title2.bold()).monospacedDigit()
                                ProgressView(value: min(week.current.seconds / 3_600, weeklyHours), total: weeklyHours).tint(HubTheme.accent)
                                Text(week.current.seconds >= weeklyHours * 3_600 ? "Your weekly time goal is reached." : "Progress toward your chosen target.").font(.caption).foregroundStyle(.secondary)
                            } else {
                                Text("Choose your own weekly target").font(.headline)
                                Text("Set a time goal that fits your plan. Zero leaves the goal off.").font(.caption).foregroundStyle(.secondary)
                            }
                            Stepper(value: $weeklyHours, in: 0...40, step: 0.5) {
                                Text(String(format: "Target: %.1f hours", weeklyHours)).font(.callout).monospacedDigit()
                            }
                        }
                    }
                    if showHealth {
                        card("Health snapshot", symbol: "heart.text.square") {
                            ForEach(["rhr", "sleep", "hrv", "stress"], id: \.self) { id in
                                if let metric = HealthMetric.all.first(where: { $0.id == id }) {
                                    let latest = model.health.days.filter { $0.source == metric.source && $0.values[id] != nil }.max { $0.day < $1.day }
                                    HStack(alignment: .top) {
                                        Text(metric.title).foregroundStyle(.secondary)
                                        Spacer()
                                        VStack(alignment: .trailing, spacing: 2) {
                                            Text(formattedHealthValue(latest?.values[id], metric: metric)).monospacedDigit()
                                            if let latest { Text(HealthAnalysis.date(latest.day)?.formatted(date: .abbreviated, time: .omitted) ?? latest.day).font(.caption2).foregroundStyle(.secondary) }
                                        }
                                    }.font(.callout)
                                }
                            }
                            Button("View health comparisons") { navigate("Health") }.buttonStyle(.link)
                            Text("Latest locally saved days; dates may differ by metric.").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                if showRecent {
                    card("Recent activities", symbol: "figure.mixed.cardio") {
                        if recent.count < 2 {
                            Text(recent.isEmpty ? "Your activities will appear here after import or Garmin sync." : "More recordings will appear here as you add them.").foregroundStyle(.secondary)
                        }
                        ForEach(recent.dropFirst()) { group in
                            Button { openActivity(group.id) } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: sportSymbol(group.summary.sport))
                                        .font(.callout.weight(.semibold)).foregroundStyle(HubTheme.accent)
                                        .frame(width: 34, height: 34)
                                        .background(HubTheme.accentWash, in: RoundedRectangle(cornerRadius: 8))
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(group.summary.title).font(.headline).lineLimit(1)
                                        Text("\(group.summary.displaySport)\(group.isMultisport ? " · \(group.sessions.count) legs" : "") · \(group.summary.start.formatted(date: .abbreviated, time: .omitted))")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 4) {
                                        Text(distance(group.summary.distance)).fontWeight(.semibold)
                                        Text(duration(group.summary.timer ?? group.summary.elapsed)).foregroundStyle(.secondary)
                                    }.font(.callout).monospacedDigit()
                                    Image(systemName: "chevron.right").foregroundStyle(.secondary)
                                }.padding(.vertical, 8).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            if group.id != recent.last?.id { Divider() }
                        }
                        Button("Browse all activities") { navigate("Activities") }.buttonStyle(.link)
                    }
                }
            }.padding(.vertical, 12)
        }
    }
    private var introduction: some View {
        VStack(alignment: .leading, spacing: 12) {
            HubEyebrow("Personal training log", color: HubTheme.accent)
            Text("A closer look at your training.")
                .hubHeading(size: 42)
                .fixedSize(horizontal: false, vertical: true)
            Text("Review your recent sessions, weekly volume and recovery in one place.")
                .font(.callout).foregroundStyle(HubTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button { navigate("Activities") } label: {
                    Label("Open activities", systemImage: "arrow.right").labelStyle(.titleAndIcon)
                }.buttonStyle(HubPillStyle(selected: true))
                if model.keyAvailable {
                    Button { model.beginSync(history: false) } label: {
                        Label("Sync Garmin", systemImage: "arrow.triangle.2.circlepath")
                    }.controlSize(.regular)
                    .disabled(model.syncing || model.healthSyncing || model.busy || model.testingConnection)
                } else {
                    SettingsLink { Text("Connect Garmin") }
                }
            }
        }.padding(.vertical, 4)
    }

    private func latestActivity(_ group: ActivityGroup) -> some View {
        let activity = group.summary
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                HubEyebrow("Latest recording", color: HubTheme.boardMuted)
                Spacer()
                Image(systemName: sportSymbol(activity.sport)).foregroundStyle(HubTheme.lime)
            }
            Text(activity.title).font(.title2.bold()).tracking(-0.55)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            Text("\(activity.displaySport) · \(activity.start.formatted(date: .abbreviated, time: .omitted))")
                .font(.caption).foregroundStyle(HubTheme.boardMuted)
            Rectangle().fill(HubTheme.boardLine).frame(height: 1)
            HStack(alignment: .top, spacing: 20) {
                featuredValue("Elapsed", duration(activity.elapsed))
                featuredValue("Distance", distance(activity.distance))
            }
            if group.isMultisport {
                ScrollView(.horizontal) {
                    HStack(spacing: 4) {
                        ForEach(group.sessions) { leg in
                            Button { openActivity(leg.id) } label: {
                                Text(group.legName(leg)).font(.caption.weight(.semibold))
                                    .padding(.vertical, 5).padding(.horizontal, 8)
                                    .background(HubTheme.boardRaised, in: RoundedRectangle(cornerRadius: 4))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Open \(group.legName(leg)) leg")
                        }
                    }
                }.scrollIndicators(.hidden)
            }
            Button { openActivity(group.id) } label: {
                HStack(spacing: 6) {
                    Text(group.isMultisport ? "Open whole activity" : "Open activity")
                    Image(systemName: "arrow.up.right")
                }.font(.callout.weight(.semibold))
                    .foregroundStyle(HubTheme.lime)
            }.buttonStyle(.plain)
        }
        .foregroundStyle(HubTheme.boardText)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HubTheme.forest, in: RoundedRectangle(cornerRadius: 15))
    }

    private func featuredValue(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(HubTheme.boardMuted)
            Text(value).font(.title3.weight(.semibold)).monospacedDigit()
        }.accessibilityElement(children: .combine)
    }

    private func card<Content: View>(_ title: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: symbol).font(.headline).foregroundStyle(HubTheme.accent)
            content()
        }.frame(maxWidth: .infinity, alignment: .leading)
            .hubPanel(padding: 16)
    }
}
