import SwiftUI
import TrainingHubCore

@MainActor @Observable
final class MapInspection {
    struct Spot {
        let point: CGPoint
        let activityIDs: [String]
    }

    private(set) var hoverCount: Int?
    var pin: Spot?
    static let hitRadius = 12.0

    func hover(_ point: CGPoint, radius: Double, on heatmap: RouteHeatmap) {
        let count = heatmap.activityCount(near: point, radius: radius)
        if hoverCount != count { hoverCount = count }
    }

    func clearHover() { hoverCount = nil }

    func select(_ point: CGPoint, radius: Double, on heatmap: RouteHeatmap, showEmpty: Bool = false) {
        let ids = heatmap.activityIDs(near: point, radius: radius)
        pin = ids.isEmpty && !showEmpty ? nil : Spot(point: point, activityIDs: ids)
    }

    static func countLabel(_ count: Int) -> String {
        "\(count.formatted()) \(count == 1 ? "activity" : "activities")"
    }
}

struct RouteMapInspection<Legend: View>: View {
    let heatmap: RouteHeatmap
    let bounds: CGRect
    let streets: Bool
    let groups: [ActivityGroup]
    let openActivity: (String) -> Void
    @ViewBuilder let legend: Legend
    @State private var inspection = MapInspection()
    @State private var centerRequest = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                legend
                Spacer()
                HoverCount(inspection: inspection)
                Button("Inspect centre") { centerRequest += 1 }
                    .controlSize(.small)
                    .help("Show recordings near the centre of the visible map.")
            }
            Group {
                if streets {
                    StreetHeatmap(heatmap: heatmap, bounds: bounds, inspection: inspection,
                                  pin: inspection.pin?.point, centerRequest: centerRequest)
                } else {
                    OfflineHeatmap(heatmap: heatmap, bounds: bounds, inspection: inspection, centerRequest: centerRequest)
                }
            }
            .frame(height: 394)
            .overlay(alignment: .topTrailing) {
                if let pin = inspection.pin {
                    let matches = Set(pin.activityIDs)
                    results(groups.filter { matches.contains($0.id) }.map(\.summary))
                        .padding(.top, streets ? 12 : 64)
                        .padding(.trailing, 12)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .onChange(of: streets) { inspection.clearHover() }
    }

    private func results(_ activities: [Activity]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("\(MapInspection.countLabel(activities.count)) at this spot", systemImage: "mappin")
                    .font(.subheadline.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button { inspection.pin = nil } label: {
                    Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(HubTheme.muted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear selected spot")
            }
            if activities.isEmpty {
                Text("Pan toward a route or choose a point on the heatmap.")
                    .font(.caption).foregroundStyle(HubTheme.muted)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(activities) { activity in
                            Button { openActivity(activity.id) } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: sportSymbol(activity.sport))
                                        .foregroundStyle(HubTheme.accent).frame(width: 16)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(activity.title).font(.callout.weight(.medium)).lineLimit(1)
                                        Text("\(activity.start.formatted(date: .abbreviated, time: .shortened)) · \(distance(activity.distance))")
                                            .font(.caption2).foregroundStyle(HubTheme.muted).lineLimit(1)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "arrow.up.right").font(.caption2).foregroundStyle(HubTheme.accent)
                                }
                                .padding(.vertical, 6).padding(.horizontal, 4)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Open \(activityMenuTitle(activity))")
                        }
                    }
                }.frame(height: min(198, CGFloat(activities.count) * 44))
            }
        }
        .frame(width: 288)
        .hubPanel(padding: 12)
        .shadow(color: .black.opacity(0.24), radius: 10, y: 4)
    }

    private struct HoverCount: View {
        let inspection: MapInspection

        var body: some View {
            Group {
                if let count = inspection.hoverCount {
                    Label("\(MapInspection.countLabel(count)) here", systemImage: "scope")
                        .foregroundStyle(count > 0 ? HubTheme.accent : HubTheme.muted)
                } else {
                    Text("Hover to count · Click to open recordings").foregroundStyle(HubTheme.muted)
                }
            }
            .font(.caption.weight(.medium)).monospacedDigit()
            .lineLimit(1)
        }
    }
}
