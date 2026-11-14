import SwiftUI
import TrainingHubCore

struct LegDurationBars: View {
    let legs: [ComparisonLeg]
    let timerBasis: Bool

    private func seconds(_ activity: Activity?) -> Double? {
        guard let activity else { return nil }
        return timerBasis ? activity.timer : activity.elapsed
    }

    var body: some View {
        let maximum = legs.lazy.flatMap { [seconds($0.selected), seconds($0.baseline)] }.compactMap { $0 }.max() ?? 0
        HubChartBoard(title: "Leg durations", subtitle: timerBasis ? "Recorded timer" : "Elapsed time") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 16) {
                    Label("Selected", systemImage: "circle.fill").foregroundStyle(HubTheme.plotPrimary)
                    Label("Baseline", systemImage: "circle.fill").foregroundStyle(HubTheme.comparison)
                }.font(.caption)
                ForEach(legs) { leg in
                    HStack(alignment: .center, spacing: 14) {
                        Text(leg.title).font(.callout.weight(.semibold))
                            .frame(width: 96, alignment: .leading)
                        VStack(spacing: 4) {
                            bar("Selected", time: seconds(leg.selected), maximum: maximum, color: HubTheme.plotPrimary)
                            bar("Baseline", time: seconds(leg.baseline), maximum: maximum, color: HubTheme.comparison)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func bar(_ title: String, time: Double?, maximum: Double, color: Color) -> some View {
        HStack(spacing: 8) {
            GeometryReader { geometry in
                Capsule().fill(HubTheme.boardRaised)
                    .overlay(alignment: .leading) {
                        if let time, maximum > 0 {
                            Capsule().fill(color)
                                .frame(width: max(0, min(1, time / maximum)) * geometry.size.width)
                        }
                    }
            }.frame(height: 6)
                .accessibilityHidden(true)
            Text(time.map(duration) ?? "—")
                .font(.caption.monospacedDigit())
                .frame(width: 65, alignment: .trailing)
                .accessibilityLabel("\(title), \(time.map(duration) ?? "unavailable")")
        }
    }
}
