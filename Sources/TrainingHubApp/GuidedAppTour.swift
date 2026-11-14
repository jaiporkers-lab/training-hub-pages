import SwiftUI

enum AppTourStep: Int, CaseIterable, Identifiable {
    case home, library, charts, laps, zones, stats, pool, performance, route, trends, calendar, goals, recovery, health, compare, map, brief, newFeatures
    var id: Int { rawValue }
    var page: String {
        switch self {
        case .home, .newFeatures: "Home"
        case .library, .charts, .laps, .zones, .stats, .pool, .performance, .route: "Activities"
        case .trends: "Trends"
        case .calendar: "Calendar"
        case .goals: "Goals"
        case .recovery: "Recovery"
        case .health: "Health"
        case .compare: "Compare"
        case .map: "Map"
        case .brief: "Coach"
        }
    }
    var section: DetailSection? {
        switch self { case .charts: .charts; case .laps: .laps; case .zones: .zones; case .stats: .stats; case .pool: .lengths; case .performance: .performance; case .route: .route; default: nil }
    }
    var title: String {
        switch self {
        case .home: "Your Home base"
        case .library: "Find any recording"
        case .charts: "Inspect the detail"
        case .laps: "Review laps and splits"
        case .zones: "Use your own zones"
        case .stats: "Find every recorded statistic"
        case .pool: "Inspect pool lengths"
        case .performance: "Look for consistency and best efforts"
        case .route: "Explore one outdoor route"
        case .trends: "See your training over time"
        case .calendar: "Plan the week"
        case .goals: "Choose a target"
        case .recovery: "Put recovery beside training"
        case .health: "Explore recorded health metrics"
        case .compare: "Compare two activities"
        case .map: "Explore your personal heatmap"
        case .brief: "Prepare a coaching brief"
        case .newFeatures: "New in GarHub"
        }
    }
    var instruction: String {
        switch self {
        case .home: "Try Customise Home at the top right. Choose a sport preset, switch cards on or off, or save your own layout. The logo and ⌘1 always bring you Home."
        case .library: "Use the sidebar search, sport, date and sort controls. Save useful filters in Views. Expand a multisport recording to select a leg, or select the whole activity. Import FIT and Garmin sync are in the toolbar."
        case .charts: "Hover over the chart to read a value and its multisport leg. Click to pin it. Choose a metric, time or distance axis and smoothing; use the range sliders for an interval. Explore Laps, Zones and All stats above the graph."
        case .laps: "Select a lap in the table to open Charts at that interval. Review recorded elapsed and timer time, distance, pace and covered heart rate. Multisport tables keep the leg name beside each lap."
        case .zones: "Enter 1–6 increasing heart-rate or power thresholds, separated by commas. Your boundaries are saved by sport. Switch to the visible chart interval to analyse a specific section; percentages use covered sensor time."
        case .stats: "Search or browse the FIT fields preserved from this recording. Recorded session values remain distinct from locally calculated summaries, and missing values stay unavailable."
        case .pool: "For a pool swim, select Pool lengths to inspect recorded lengths, active lengths, rest, strokes and SWOLF. This section only appears for swimming, and the available detail depends on the recording."
        case .performance: "For a run, open Performance to inspect kilometre splits and compare steady sections with HR drift and coverage checks. For a ride, inspect 5-second to 60-minute power efforts and enter your own FTP."
        case .route: "Choose heart rate, pace, power or elevation for the track colour. Scroll to the elevation profile, detected climbs and Find similar recordings. Use Compare profile on a match, or open it. The street basemap can be turned off."
        case .trends: "Choose a period and sport to review weekly time and distance against the preceding period. A multisport recording counts once, with volume split across its recorded legs."
        case .calendar: "Use New plan or Add plan on a day to create a workout or race. Drag a planned card onto another day to reschedule. Select a completed recording to open its analysis. Undo last change reverses an edit. Watch calendar explains Garmin’s current sync restriction and the manual scheduling route."
        case .goals: "Enter weekly hours, weekly kilometres or a distance milestone; zero turns a goal off. Choose running or cycling, then Calculate recorded bests to scan your local recordings. Select a result to open its activity."
        case .recovery: "Pick a health metric and history range. Hover either plot to inspect the same date. Compare the last seven days with the previous 28, then explore same-day or next-day associations. Missing health stays empty."
        case .health: "Pick a recorded metric and comparison period. Sync health fetches supported Garmin summaries in batches. Coverage counts show which days were recorded; longer recovery views use history already saved on this Mac."
        case .compare: "Choose two recordings, then select an analysis metric. Align by elapsed time, distance or relative progress where available. Multisport comparisons let you match legs and compare the whole recording."
        case .map: "Filter outdoor recordings by date, sport or activity. Pan and zoom the heatmap. Hover to count recordings near the pointer, then click to pin a spot and open a recording. Inspect centre is an alternative. Indoor and virtual sessions are excluded."
        case .brief: "Choose what to include, review the prepared text and copy it yourself if useful. Health is optional. This builder runs locally and makes no AI calls. Settings → Library contains backups and restore."
        case .newFeatures: "The blue options below are new in this update. Revisit any section, or finish the tour. You can replay this live guide from the question-mark toolbar button at any time."
        }
    }
}

struct GuidedAppTourCard: View {
    let step: AppTourStep
    let missingRecording: Bool
    let move: (Int) -> Void
    let finish: () -> Void
    let explore: (AppTourStep) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                Label("APP WALKTHROUGH", systemImage: "location.north.circle.fill").font(.caption2.bold()).tracking(1).foregroundStyle(HubTheme.accent)
                Text("\(step.rawValue + 1) / \(AppTourStep.allCases.count)").font(.caption).monospacedDigit().foregroundStyle(.secondary)
                Spacer()
                Button("Show this section") { explore(step) }.buttonStyle(.link).font(.caption)
                Button("End tour", action: finish).buttonStyle(.link).font(.caption)
            }
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(step.title).font(.headline)
                    Text(step.instruction).font(.callout).foregroundStyle(HubTheme.muted).fixedSize(horizontal: false, vertical: true)
                    if missingRecording {
                        Text("No suitable recording is loaded yet. Import a matching FIT file or sync Garmin to try this section; you can still continue the tour.").font(.caption).foregroundStyle(HubTheme.accent)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 8) {
                    Button("Back") { move(-1) }.disabled(step == .home)
                    Button(step == .newFeatures ? "Finish tour" : "Next section") { step == .newFeatures ? finish() : move(1) }.buttonStyle(.borderedProminent)
                }.fixedSize()
            }
            if step == .newFeatures {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), alignment: .leading, spacing: 7) {
                    ForEach([AppTourStep.performance, .route, .calendar, .goals, .recovery, .home]) { item in
                        Button { explore(item) } label: {
                            Text("NEW · \(item == .home ? "Home presets" : item == .performance ? "Performance" : item == .route ? "Route" : item.title.replacingOccurrences(of: "Plan the week", with: "Calendar").replacingOccurrences(of: "Choose a target", with: "Goals").replacingOccurrences(of: "Put recovery beside training", with: "Recovery"))").font(.caption.weight(.semibold))
                        }.buttonStyle(HubPillStyle(selected: true))
                    }
                }
            }
        }.padding(15).background(HubTheme.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(HubTheme.accent, lineWidth: 2))
            .accessibilityElement(children: .contain)
    }
}
