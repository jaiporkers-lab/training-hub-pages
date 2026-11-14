import Foundation

public struct RouteVertex: Identifiable, Sendable {
    public let id: Int
    public let segment: Int
    public let latitude: Double
    public let longitude: Double
    public let elapsed: Double
    public let distance: Double?
    public let altitude: Double?
    public let value: Double?
}
public struct RouteClimb: Identifiable, Sendable {
    public let id: Int
    public let start: Double
    public let end: Double
    public let meters: Double
    public let gain: Double
    public var grade: Double { gain / meters * 100 }
}
public struct RouteMatch: Identifiable, Sendable {
    public var id: String { activity.id }
    public let activity: Activity
    public let overlap: Double
}
public enum RouteAnalysis {
    /// Invalid fixes, recording gaps and implausible jumps break a track.
    public static func vertices(_ samples: [Sample], metric: Metric) throws -> [RouteVertex] {
        var result: [RouteVertex] = []
        var segment = 0
        var previous: Sample?
        for (index, sample) in samples.enumerated() {
            if index.isMultiple(of: 512) { try Task.checkCancellation() }
            guard sample.elapsed.isFinite, let lat = sample.latitude, let lon = sample.longitude,
                  lat.isFinite, lon.isFinite, (-85.05112878...85.05112878).contains(lat), (-180...180).contains(lon) else {
                segment += 1; previous = nil; continue
            }
            if let last = previous, let a = last.latitude, let b = last.longitude {
                let dt = sample.elapsed - last.elapsed
                if dt <= 0 || dt > 30 || separation(a, b, lat, lon) > min(600, max(30, dt * 45)) { segment += 1 }
            }
            result.append(RouteVertex(id: sample.id, segment: segment, latitude: lat, longitude: lon,
                                      elapsed: sample.elapsed, distance: sample.distance, altitude: sample.altitude,
                                      value: metric.value(sample).flatMap { $0.isFinite ? $0 : nil }))
            previous = sample
        }
        // Bound map rendering work without joining separate valid spans.
        if result.count <= 3_000 { return result }
        let stride = max(1, Int(ceil(Double(result.count) / 2_500)))
        return result.enumerated().compactMap { index, point in
            index == 0 || index == result.count - 1 || index.isMultiple(of: stride) ||
            result[index - 1].segment != point.segment || result[min(result.count - 1, index + 1)].segment != point.segment ? point : nil
        }
    }

    /// A climb rises at least 50 m over 300 m; an 8 m descent ends it.
    public static func climbs(_ samples: [Sample]) -> [RouteClimb] {
        struct Fix { let time: Double; let distance: Double; let height: Double }
        var runs: [[Fix]] = [], run: [Fix] = []
        for sample in samples {
            guard sample.elapsed.isFinite, let distance = sample.distance, distance.isFinite, distance >= 0,
                  let height = sample.altitude, height.isFinite else {
                if !run.isEmpty { runs.append(run); run = [] }; continue
            }
            if let last = run.last, sample.elapsed <= last.time || sample.elapsed - last.time > 30 || distance < last.distance {
                runs.append(run); run = []
            }
            run.append(Fix(time: sample.elapsed, distance: distance, height: height))
        }
        if !run.isEmpty { runs.append(run) }
        var result: [RouteClimb] = []
        for run in runs where run.count >= 3 {
            // Smooth at roughly 20 m spacing to reduce altitude noise.
            var spaced = [run[0]]
            for fix in run.dropFirst() where fix.distance - spaced.last!.distance >= 20 { spaced.append(fix) }
            guard spaced.count >= 3 else { continue }
            let smoothed = spaced.indices.map { index -> Fix in
                let window = spaced[max(0, index - 2)...min(spaced.count - 1, index + 2)]
                return Fix(time: spaced[index].time, distance: spaced[index].distance, height: window.map(\.height).reduce(0, +) / Double(window.count))
            }
            var low = smoothed[0], peak = low
            func appendClimb() {
                let meters = peak.distance - low.distance, gain = peak.height - low.height
                if meters >= 300, gain >= 50 {
                    result.append(RouteClimb(id: result.count + 1, start: low.time, end: peak.time, meters: meters, gain: gain))
                }
            }
            for fix in smoothed.dropFirst() {
                if fix.height > peak.height { peak = fix }
                if peak.height - fix.height >= 8 { appendClimb(); low = fix; peak = fix }
                else if fix.height < low.height { low = fix; peak = fix }
            }
            appendClimb()
        }
        return result
    }

    struct Cell: Hashable, Sendable { let x: Int; let y: Int }
    struct Signature: Sendable { let cells: Set<Cell>; let size: Double }
    static func signature(_ samples: [Sample], size: Double) throws -> Signature {
        let points = try vertices(samples, metric: .altitude)
        return Signature(cells: Set(points.map {
            Cell(x: Int(floor(($0.longitude + 180) / 360 * 40_075_017 / size)),
                 y: Int(floor(asinh(tan($0.latitude * .pi / 180)) * 6_378_137 / size)))
        }), size: size)
    }
    static func overlap(_ a: Signature, _ b: Signature) -> Double {
        guard a.cells.count >= 5, b.cells.count >= 5 else { return 0 }
        func covered(_ first: Set<Cell>, _ second: Set<Cell>) -> Double {
            let matches = first.filter { cell in
                (-1...1).contains { dx in (-1...1).contains { dy in second.contains(Cell(x: cell.x + dx, y: cell.y + dy)) } }
            }.count
            return Double(matches) / Double(first.count)
        }
        return min(covered(a.cells, b.cells), covered(b.cells, a.cells))
    }
    private static func separation(_ a: Double, _ b: Double, _ c: Double, _ d: Double) -> Double {
        let lat = (c - a) * .pi / 180, lon = (d - b) * .pi / 180
        let x = pow(sin(lat / 2), 2) + cos(a * .pi / 180) * cos(c * .pi / 180) * pow(sin(lon / 2), 2)
        return 12_742_000 * asin(sqrt(min(1, max(0, x))))
    }
}
extension ActivityStore {
    public func repeatedRoutes(activity: Activity, samples: [Sample], activities: [Activity],
                               progress: @Sendable (Int, Int) async -> Void) async throws -> [RouteMatch] {
        guard let meters = activity.distance, meters >= 500,
              let latitude = samples.compactMap(\.latitude).first else { return [] }
        let size = 100 / max(0.1, cos(latitude * .pi / 180))
        let selected = try RouteAnalysis.signature(samples, size: size)
        let eligible = activities.filter { candidate in
            guard candidate.id != activity.id, candidate.sport == activity.sport, candidate.sessionIndex >= 0,
                  candidate.isOutdoorRouteCandidate, let distance = candidate.distance else { return false }
            return abs(distance / meters - 1) <= 0.2
        }
        var matches: [RouteMatch] = []
        for (index, candidate) in eligible.enumerated() {
            try Task.checkCancellation()
            let signature = try RouteAnalysis.signature(try self.samples(for: candidate.id), size: size)
            let overlap = RouteAnalysis.overlap(selected, signature)
            if overlap >= 0.65 { matches.append(RouteMatch(activity: candidate, overlap: overlap)) }
            if index.isMultiple(of: 8) || index == eligible.count - 1 { await progress(index + 1, eligible.count) }
            await Task.yield()
        }
        return matches.sorted { $0.overlap > $1.overlap }
    }
}
