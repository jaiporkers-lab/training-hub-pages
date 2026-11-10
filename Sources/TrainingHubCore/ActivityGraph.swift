import Foundation

public enum ActivityGraph {
    public struct Point: Identifiable, Sendable {
        public let id: Int
        public let x: Double
        public let y: Double
        public let segment: Int
    }

    public static func points(_ samples: [Sample], metric: Metric, distanceAxis: Bool,
                              smoothing: Double, breaks: [Double], swimPace: Bool) -> [Point] {
        let values = Analysis.smoothedValues(samples, metric: metric, window: smoothing, breaks: breaks)
        var segment = 0
        var previous: (elapsed: Double, x: Double)?
        return samples.enumerated().compactMap { index, sample in
            let axis = distanceAxis ? sample.distance.map { $0 / 1_000 } : sample.elapsed / 60
            guard let x = axis, x.isFinite, x >= 0, let value = values[index], value.isFinite else {
                if previous != nil { segment += 1 }
                previous = nil
                return nil
            }
            if let previous, sample.elapsed - previous.elapsed > 30 || x < previous.x ||
                breaks.contains(where: { previous.elapsed < $0 && $0 <= sample.elapsed }) {
                segment += 1
            }
            previous = (sample.elapsed, x)
            return Point(id: index, x: x, y: metric == .pace && swimPace ? value / 10 : value, segment: segment)
        }
    }

    /// Reduce marks on dense runs while retaining the first, last and extreme readings
    /// in each bucket. The inspection index still uses the complete source recording.
    public static func displayPoints(_ points: [Point], target: Int = 2_000) -> [Point] {
        guard target >= 4, points.count > target else { return points }
        let bucket = Int(ceil(Double(points.count) / Double(target / 4)))
        var output: [Point] = []
        var start = 0
        while start < points.count {
            var end = start + 1
            var low = start
            var high = start
            while end < points.count, end - start < bucket, points[end].segment == points[start].segment {
                if points[end].y < points[low].y { low = end }
                if points[end].y > points[high].y { high = end }
                end += 1
            }
            if end - start <= 4 {
                output.append(contentsOf: points[start..<end])
            } else {
                for index in Set([start, low, high, end - 1]).sorted() { output.append(points[index]) }
            }
            start = end
        }
        return output
    }

    /// Prefer a sensor both recordings have, then fall back to a sensor either recorded.
    public static func preferredMetric(_ preferred: Metric, selected: [Sample], baseline: [Sample]) -> Metric {
        let order = [preferred] + Metric.allCases.filter { $0 != preferred }
        var fallback: Metric?
        for metric in order {
            let left = selected.contains { Analysis.validValue(metric, $0) != nil }
            let right = baseline.contains { Analysis.validValue(metric, $0) != nil }
            if left && right { return metric }
            if fallback == nil && (left || right) { fallback = metric }
        }
        return fallback ?? preferred
    }
}
