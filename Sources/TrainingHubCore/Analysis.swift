import Foundation

public struct MetricSummary: Sendable {
    public let average: Double?
    public let minimum: Double?
    public let maximum: Double?
    public let coveredSeconds: Double
    public let sampleCount: Int
}

public struct IntervalAnalysis: Sendable {
    public let start: Double
    public let end: Double
    public let distance: Double?
    public let heartRate: MetricSummary
    public let power: MetricSummary
    public let speed: MetricSummary
    public var elapsed: Double { max(0, end - start) }
}

public struct ZoneBin: Identifiable, Sendable {
    public let id: Int
    public let lower: Double?
    public let upper: Double?
    public var seconds: Double
}

public struct ZoneDistribution: Sendable {
    public let bins: [ZoneBin]
    public let coveredSeconds: Double
    public let excludedSeconds: Double
}

public struct AnalysisLap: Identifiable, Sendable {
    public let id: String
    public let leg: String
    public let sport: String
    public let index: Int
    public let start: Double?
    public let end: Double?
    public let elapsed: Double?
    public let timer: Double?
    public let distance: Double?
    public var averageSpeed: Double? {
        guard let distance, let timer, timer > 0 else { return nil }
        return distance / timer
    }
}

public enum Analysis {
    /// Samples describe elapsed coverage, not active timer-event intervals. Never bridge a long gap.
    public static func summary(_ samples: [Sample], metric: Metric, start: Double, end: Double, maxGap: Double = 30) -> MetricSummary {
        let observed = samples.filter { $0.elapsed >= start && $0.elapsed <= end }.compactMap { validValue(metric, $0) }
        var weighted = 0.0
        var covered = 0.0
        forEachInterval(samples, start: start, end: end, maxGap: maxGap) { sample, duration in
            guard let value = validValue(metric, sample) else { return }
            weighted += value * duration
            covered += duration
        }
        return MetricSummary(average: covered > 0 ? weighted / covered : nil, minimum: observed.min(), maximum: observed.max(),
                             coveredSeconds: covered, sampleCount: observed.count)
    }

    public static func interval(_ samples: [Sample], start: Double, end: Double) -> IntervalAnalysis {
        let end = max(start, end)
        let distance: Double?
        if let from = distanceAt(start, samples: samples), let to = distanceAt(end, samples: samples), to >= from {
            distance = to - from
        } else { distance = nil }
        return IntervalAnalysis(start: start, end: end, distance: distance,
            heartRate: summary(samples, metric: .heartRate, start: start, end: end),
            power: summary(samples, metric: .power, start: start, end: end),
            speed: summary(samples, metric: .speed, start: start, end: end))
    }

    public static func parseZoneBoundaries(_ text: String) throws -> [Double] {
        let fields = text.components(separatedBy: CharacterSet(charactersIn: ",; \n\t")).filter { !$0.isEmpty }
        let values = fields.compactMap(Double.init)
        guard (1...6).contains(values.count), values.count == fields.count,
              values.allSatisfy({ $0.isFinite && $0 > 0 }), zip(values, values.dropFirst()).allSatisfy({ $0 < $1 }) else {
            throw HubError.message("Enter 1–6 positive, increasing boundaries separated by commas.")
        }
        return values
    }

    public static func zones(_ samples: [Sample], metric: Metric, boundaries: [Double], start: Double, end: Double, maxGap: Double = 30) -> ZoneDistribution {
        var bins = (0...boundaries.count).map { index in
            ZoneBin(id: index + 1, lower: index == 0 ? nil : boundaries[index - 1],
                    upper: index == boundaries.count ? nil : boundaries[index], seconds: 0)
        }
        forEachInterval(samples, start: start, end: end, maxGap: maxGap) { sample, duration in
            guard let value = validValue(metric, sample) else { return }
            let index = boundaries.firstIndex { value < $0 } ?? boundaries.count
            bins[index].seconds += duration
        }
        let covered = bins.reduce(0) { $0 + $1.seconds }
        return ZoneDistribution(bins: bins, coveredSeconds: covered, excludedSeconds: max(0, end - start - covered))
    }

    public static func laps(activity: Activity, group: ActivityGroup?) -> [AnalysisLap] {
        let whole = activity.id.hasPrefix(ActivityGroup.idPrefix)
        let sessions = whole ? (group?.sessions ?? []) : [activity]
        return sessions.flatMap { session in
            session.laps.enumerated().map { index, lap in
                let start = lap.start.map { $0.timeIntervalSince(activity.start) }
                let nextStart = index + 1 < session.laps.count ? session.laps[index + 1].start : nil
                let end: Double?
                if let start, let elapsed = lap.elapsed { end = start + elapsed }
                else if let nextStart { end = nextStart.timeIntervalSince(activity.start) }
                else { end = session.start.addingTimeInterval(session.elapsed).timeIntervalSince(activity.start) }
                return AnalysisLap(id: "\(session.id):lap:\(index)", leg: group?.legName(session) ?? session.displaySport,
                    sport: session.sport, index: index + 1, start: start, end: end, elapsed: lap.elapsed,
                    timer: lap.timer, distance: lap.distance)
            }
        }
    }

    /// Centred sample mean, kept within each uninterrupted sensor segment. Raw statistics are unaffected.
    public static func smoothedValues(_ samples: [Sample], metric: Metric, window: Double, breaks: [Double] = []) -> [Double?] {
        let values = samples.map { validValue(metric, $0) }
        guard window > 0, !samples.isEmpty else { return values }
        var result = values
        var segmentStart = 0
        func process(_ range: Range<Int>) {
            var left = range.lowerBound
            var right = range.lowerBound
            var sum = 0.0
            for index in range {
                let from = samples[index].elapsed - window / 2
                let to = samples[index].elapsed + window / 2
                while right < range.upperBound && samples[right].elapsed <= to { sum += values[right]!; right += 1 }
                while left < right && samples[left].elapsed < from { sum -= values[left]!; left += 1 }
                result[index] = right > left ? sum / Double(right - left) : values[index]
            }
        }
        for index in samples.indices {
            let boundary = index > 0 && (samples[index].elapsed - samples[index - 1].elapsed > 30 ||
                breaks.contains { $0 > samples[index - 1].elapsed && $0 <= samples[index].elapsed })
            if values[index] == nil || boundary {
                if segmentStart < index { process(segmentStart..<index) }
                segmentStart = values[index] == nil ? index + 1 : index
            }
        }
        if segmentStart < samples.count { process(segmentStart..<samples.count) }
        return result
    }

    static func validValue(_ metric: Metric, _ sample: Sample) -> Double? {
        guard let value = metric.value(sample), value.isFinite, metric != .heartRate || value > 0 else { return nil }
        return value
    }

    private static func forEachInterval(_ samples: [Sample], start: Double, end: Double, maxGap: Double,
                                        _ visit: (Sample, Double) -> Void) {
        guard samples.count > 1, end > start else { return }
        for index in 0..<(samples.count - 1) {
            let sample = samples[index]
            let next = samples[index + 1]
            let gap = next.elapsed - sample.elapsed
            guard gap > 0, gap <= maxGap else { continue }
            let duration = min(end, next.elapsed) - max(start, sample.elapsed)
            if duration > 0 { visit(sample, duration) }
        }
    }

    private static func distanceAt(_ time: Double, samples: [Sample]) -> Double? {
        if let exact = samples.first(where: { abs($0.elapsed - time) < 0.000_001 }) { return exact.distance }
        guard let next = samples.firstIndex(where: { $0.elapsed > time }), next > 0 else { return nil }
        let before = samples[next - 1]
        let after = samples[next]
        let gap = after.elapsed - before.elapsed
        guard gap > 0, gap <= 30, let from = before.distance, let to = after.distance, to >= from else { return nil }
        return from + (to - from) * (time - before.elapsed) / gap
    }
}
