import Foundation

/// A reusable coordinate index. Distance regressions and missing readings do not
/// change source order or require a full sensor scan during pointer movement.
public struct SampleInspectionIndex: Sendable {
    private struct Entry: Sendable { let coordinate: Double; let source: Int }
    private let entries: [Entry]
    public var maximumAxis: Double? { entries.last?.coordinate }

    public init(samples: [Sample] = [], distanceAxis: Bool = false) {
        entries = samples.enumerated().compactMap { index, sample in
            let value = distanceAxis ? sample.distance.map { $0 / 1_000 } : sample.elapsed / 60
            guard let value, value.isFinite else { return nil }
            return Entry(coordinate: value, source: index)
        }.sorted { $0.coordinate == $1.coordinate ? $0.source < $1.source : $0.coordinate < $1.coordinate }
    }

    public func nearest(to coordinate: Double, tolerance: Double) -> Int? {
        guard coordinate.isFinite, tolerance >= 0, !entries.isEmpty else { return nil }
        func lowerBound(_ value: Double) -> Int {
            var lower = 0, upper = entries.count
            while lower < upper {
                let middle = lower + (upper - lower) / 2
                if entries[middle].coordinate < value { lower = middle + 1 }
                else { upper = middle }
            }
            return lower
        }
        let insertion = lowerBound(coordinate)
        var candidate = insertion < entries.count ? entries[insertion] : nil
        if insertion > 0 {
            // Use the earliest source reading when the left coordinate repeats.
            let left = entries[lowerBound(entries[insertion - 1].coordinate)]
            if let current = candidate {
                let leftDistance = abs(left.coordinate - coordinate), rightDistance = abs(current.coordinate - coordinate)
                if leftDistance < rightDistance || (leftDistance == rightDistance && left.source < current.source) { candidate = left }
            } else { candidate = left }
        }
        guard let candidate, abs(candidate.coordinate - coordinate) <= tolerance else { return nil }
        return candidate.source
    }
}
