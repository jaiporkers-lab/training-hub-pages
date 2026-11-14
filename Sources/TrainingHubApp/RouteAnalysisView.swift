import SwiftUI
import Charts
import MapKit
import TrainingHubCore

struct RouteAnalysisView: View {
    let activity: Activity
    let samples: [Sample]
    let all: [Activity]
    let store: ActivityStore
    let openActivity: (String) -> Void
    @State private var metric: Metric = .heartRate
    @State private var vertices: [RouteVertex] = []
    @State private var climbs: [RouteClimb] = []
    @State private var matches: [RouteMatch] = []
    @State private var scanID = 0
    @State private var scanning = false
    @State private var progress = ""
    @State private var error: String?
    @State private var compareID = ""
    @State private var compared: [Sample] = []
    @AppStorage("map.showStreetBasemap") private var streets = true
    private var scale: ClosedRange<Double>? {
        let values = vertices.compactMap(\.value)
        guard let low = values.min(), let high = values.max() else { return nil }
        return low...max(low + 0.01, high)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Route analysis").font(.title2.bold())
                Spacer()
                Picker("Track colour", selection: $metric) {
                    ForEach([Metric.heartRate, .pace, .power, .altitude]) { Text($0.rawValue).tag($0) }
                }.frame(width: 220)
                Toggle("Street basemap", isOn: $streets).toggleStyle(.switch).fixedSize()
            }
            if vertices.count >= 2 {
                if streets { MetricRouteMap(vertices: vertices, scale: scale).frame(height: 360).id("\(activity.id)-\(metric.rawValue)-\(vertices.count)").clipShape(RoundedRectangle(cornerRadius: 12)) }
                else { OfflineMetricRoute(vertices: vertices, scale: scale).frame(height: 360).background(HubTheme.boardBackground, in: RoundedRectangle(cornerRadius: 12)) }
                HStack(spacing: 12) {
                    Text(metric.rawValue).font(.caption.bold())
                    if let scale {
                        Text(routeValue(scale.lowerBound, metric))
                        LinearGradient(colors: [routeColor(0), routeColor(0.5), routeColor(1)], startPoint: .leading, endPoint: .trailing).frame(width: 130, height: 7).clipShape(Capsule())
                        Text(routeValue(scale.upperBound, metric))
                    }
                    Text("Grey = missing reading").foregroundStyle(.secondary)
                }.font(.caption).monospacedDigit()
                if streets { Text("Apple Maps supplies the optional basemap and receives the viewed map area. Recorded tracks and analysis stay on this Mac.").font(.caption).foregroundStyle(.secondary) }
            } else { ContentUnavailableView("No usable outdoor route", systemImage: "map", description: Text("This view needs recorded GPS coordinates. Indoor and virtual activities are excluded.")) }
            elevationChart
            Text("Detected climbs").font(.headline)
            if climbs.isEmpty { Text("No climbs meet the 50 m rise and 300 m distance thresholds with continuous distance/elevation coverage.").font(.callout).foregroundStyle(.secondary) }
            ForEach(climbs) { climb in
                HStack { Text("Climb \(climb.id)").fontWeight(.semibold); Text("\(duration(climb.start))–\(duration(climb.end))"); Spacer(); Text(distance(climb.meters)); Text(String(format: "+%.0f m · %.1f%%", climb.gain, climb.grade)) }.monospacedDigit().hubPanel(padding: 12)
            }
            Text("Elevation is smoothed over five points spaced about 20 m apart. A descent of 8 m ends a climb. Gain and grade describe the smoothed net rise, not certified segments.").font(.caption).foregroundStyle(.secondary)
            Divider()
            HStack {
                Text("Repeated routes").font(.title3.bold()); Spacer()
                Button(scanning ? "Cancel" : "Find similar recordings") { scanID = scanning ? 0 : scanID + 1 }.disabled(vertices.count < 2 || (activity.distance ?? 0) < 500)
            }
            Text("Matches use approximate GPS footprint overlap within neighbouring 100 m cells, the same sport and distance within 20%. Routes must be at least 500 m. Direction, exact course and conditions may differ.").font(.caption).foregroundStyle(.secondary)
            if scanning { HStack { ProgressView().controlSize(.small); Text(progress).font(.caption) } }
            if let error { Text(error).foregroundStyle(.red) }
            if !progress.isEmpty && !scanning && matches.isEmpty { Text("No similar routes found among the imported recordings.").foregroundStyle(.secondary) }
            ForEach(matches) { match in
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(activityMenuTitle(match.activity)).font(.headline).lineLimit(2)
                        Text(String(format: "%.0f%% footprint coverage", match.overlap * 100)).font(.caption).foregroundStyle(.secondary)
                        Text("Selected − match: \(routeDelta(activity.timer ?? activity.elapsed, match.activity.timer ?? match.activity.elapsed, scale: 1 / 60, unit: "min")) · \(routeDelta(activity.avgHeartRate, match.activity.avgHeartRate, unit: "bpm")) · \(routeDelta(activity.avgPower, match.activity.avgPower, unit: "W"))").font(.caption).monospacedDigit()
                    }
                    Spacer()
                    Button(compareID == match.id ? "Comparing" : "Compare profile") { compareID = match.id }
                    Button("Open") { openActivity(match.id) }
                }.hubPanel(padding: 14)
            }
            if !compared.isEmpty {
                HStack { Text("Elevation comparison by recorded distance").font(.headline); Spacer(); Button("Clear comparison") { compareID = ""; compared = [] } }
                comparisonChart
            }
        }
        .task(id: "\(samples.count)-\(metric.rawValue)") {
            let data = samples, selected = metric
            let job = Task.detached(priority: .userInitiated) { (try RouteAnalysis.vertices(data, metric: selected), RouteAnalysis.climbs(data)) }
            do {
                let result = try await withTaskCancellationHandler(operation: { try await job.value }, onCancel: { job.cancel() })
                if !Task.isCancelled { vertices = result.0; climbs = result.1 }
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
        .task(id: scanID) {
            guard scanID > 0 else { scanning = false; return }
            scanning = true; matches = []; progress = "Reading route footprints…"; error = nil
            defer { if !Task.isCancelled { scanning = false } }
            do {
                let result = try await store.repeatedRoutes(activity: activity, samples: samples, activities: all) { done, total in
                    await MainActor.run { progress = "\(done) of \(total) candidates" }
                }
                if !Task.isCancelled { matches = result }
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
        .task(id: compareID) {
            guard !compareID.isEmpty else { compared = []; return }
            do { let data = try await store.samples(for: compareID); if !Task.isCancelled { compared = data } }
            catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
    private var elevationChart: some View {
        HubChartBoard(title: "Elevation profile", subtitle: "Recorded distance · valid route spans") {
            Chart(vertices.filter { $0.altitude != nil && $0.distance != nil }) { point in
                LineMark(x: .value("km", point.distance! / 1_000), y: .value("m", point.altitude!), series: .value("Span", point.segment)).foregroundStyle(HubTheme.plotPrimary)
            }.chartYAxisLabel("m").chartXAxisLabel("km").chartYScale(domain: .automatic(includesZero: false))
                .chartOverlay { proxy in
                    ChartInspectionOverlay(proxy: proxy, reset: activity.id) { (x: Double) in
                        if let point = vertices.filter({ $0.distance != nil }).min(by: { abs($0.distance! / 1_000 - x) < abs($1.distance! / 1_000 - x) }), abs(point.distance! / 1_000 - x) < 0.1 {
                            Text(distance(point.distance)).bold(); Text("Elevation \(number(point.altitude, unit: "m"))"); Text("Elapsed \(duration(point.elapsed))")
                        } else { Text("No nearby recorded point") }
                    }
                }.frame(height: 210)
        }
    }
    private var comparisonChart: some View {
        let selected = activityPlotPoints(samples, activity: activity, group: nil, metric: .altitude, distanceAxis: true, smoothing: 0, series: "Selected", prefix: "a")
        let match = all.first { $0.id == compareID } ?? activity
        let other = activityPlotPoints(compared, activity: match, group: nil, metric: .altitude, distanceAxis: true, smoothing: 0, series: "Comparison", prefix: "b")
        return HubChartBoard(title: "Route profiles", subtitle: "Blue selected · amber comparison · exact course is not aligned") {
            Chart(selected + other) { point in
                LineMark(x: .value("km", point.x), y: .value("m", point.y), series: .value("Span", point.segment)).foregroundStyle(point.series == "Selected" ? HubTheme.plotPrimary : HubTheme.comparison)
            }.chartXAxisLabel("km").chartYAxisLabel("m").chartYScale(domain: .automatic(includesZero: false))
                .chartOverlay { proxy in
                    ChartInspectionOverlay(proxy: proxy, reset: compareID) { (x: Double) in
                        Text(String(format: "%.2f km", x)).bold()
                        forProfileReadout(selected, x: x, label: "Selected")
                        forProfileReadout(other, x: x, label: "Comparison")
                    }
                }.frame(height: 220)
        }
    }
    private func forProfileReadout(_ data: [PlotPoint], x: Double, label: String) -> some View {
        let point = data.min { abs($0.x - x) < abs($1.x - x) }
        return Text("\(label): \(point.flatMap { abs($0.x - x) < 0.1 ? number($0.y, unit: "m") : nil } ?? "—")")
    }
}

private func routeColor(_ fraction: Double) -> Color { Color(hue: 0.62 * (1 - min(1, max(0, fraction))), saturation: 0.85, brightness: 0.95) }
private func routeValue(_ value: Double, _ metric: Metric) -> String { metric == .pace ? "\(paceMinutes(value)) /km" : number(value, unit: metric.unit) }
private func fraction(_ value: Double?, _ scale: ClosedRange<Double>?) -> Double? {
    guard let value, let scale else { return nil }
    return (value - scale.lowerBound) / (scale.upperBound - scale.lowerBound)
}
private struct MetricRouteMap: NSViewRepresentable {
    let vertices: [RouteVertex]
    let scale: ClosedRange<Double>?
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> MKMapView {
        let map = FittedMetricMap(); map.delegate = context.coordinator
        map.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
        map.showsUserLocation = false; map.isPitchEnabled = false; map.isRotateEnabled = false; map.showsScale = true
        var paths = [Int: [MKPolyline]]()
        var bounds = MKMapRect.null
        for (a, b) in zip(vertices, vertices.dropFirst()) where a.segment == b.segment {
            var coordinates = [CLLocationCoordinate2D(latitude: a.latitude, longitude: a.longitude), CLLocationCoordinate2D(latitude: b.latitude, longitude: b.longitude)]
            let line = MKPolyline(coordinates: &coordinates, count: 2)
            let bin = fraction(a.value, scale).map { min(11, max(0, Int($0 * 11))) } ?? -1
            paths[bin, default: []].append(line); bounds = bounds.union(line.boundingMapRect)
        }
        for (bin, lines) in paths {
            let overlay = MKMultiPolyline(lines); overlay.title = String(bin); map.addOverlay(overlay)
        }
        if !bounds.isNull { map.initialRect = bounds }
        return map
    }
    func updateNSView(_ map: MKMapView, context: Context) {}
    final class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let line = overlay as? MKMultiPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKMultiPolylineRenderer(multiPolyline: line)
            let bin = Int(line.title ?? "-1") ?? -1
            renderer.strokeColor = bin < 0 ? .systemGray : NSColor(routeColor(Double(bin) / 11))
            renderer.lineWidth = 4; renderer.lineJoin = .round; renderer.lineCap = .round
            return renderer
        }
    }
    private final class FittedMetricMap: MKMapView {
        var initialRect: MKMapRect?
        override func layout() {
            super.layout()
            if bounds.width > 70, bounds.height > 70, let rect = initialRect {
                initialRect = nil; setVisibleMapRect(rect, edgePadding: NSEdgeInsets(top: 35, left: 35, bottom: 35, right: 35), animated: false)
            }
        }
    }
}
private struct OfflineMetricRoute: View {
    let vertices: [RouteVertex]
    let scale: ClosedRange<Double>?
    var body: some View {
        Canvas { context, size in
            let points = vertices.map { vertex -> CGPoint in
                CGPoint(x: vertex.longitude, y: -asinh(tan(vertex.latitude * .pi / 180)) * 180 / .pi)
            }
            guard let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(), let minY = points.map(\.y).min(), let maxY = points.map(\.y).max() else { return }
            let zoom = min((size.width - 40) / max(0.00001, maxX - minX), (size.height - 40) / max(0.00001, maxY - minY))
            func project(_ point: CGPoint) -> CGPoint { CGPoint(x: (point.x - (minX + maxX) / 2) * zoom + size.width / 2, y: (point.y - (minY + maxY) / 2) * zoom + size.height / 2) }
            for index in 0..<max(0, vertices.count - 1) where vertices[index].segment == vertices[index + 1].segment {
                var path = Path(); path.move(to: project(points[index])); path.addLine(to: project(points[index + 1]))
                let colour = fraction(vertices[index].value, scale).map(routeColor) ?? .gray
                context.stroke(path, with: .color(colour), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
        }.accessibilityLabel("Offline metric-coloured route, without a street basemap")
    }
}

private func routeDelta(_ lhs: Double?, _ rhs: Double?, scale: Double = 1, unit: String) -> String {
    guard let lhs, let rhs else { return "—" }
    return String(format: "%+.1f %@", (lhs - rhs) * scale, unit)
}
