import Foundation

public struct PowerEffort: Identifiable, Sendable {
    public var id: Double { seconds }
    public let seconds: Double
    public let watts: Double?
    public let start: Double?
}

public struct DistanceEffort: Identifiable, Sendable {
    public var id: Double { meters }
    public let meters: Double
    public let seconds: Double?
    public let start: Double?
}

public struct RunningSplit: Identifiable, Sendable {
    public var id: Int { number }
    public let number: Int
    public let meters: Double
    public let start: Double
    public let end: Double
    public let heartRate: Double?
    public let heartRateCoverage: Double
    public var secondsPerKilometer: Double { (end - start) / meters * 1_000 }
}

public struct SteadyEffort: Sendable {
    public let averageSpeed: Double?
    public let averageHeartRate: Double?
    public let coverage: Double
    public let driftPercent: Double?
    public let paceVariationPercent: Double?
}

public enum PerformanceAnalysis {
    public static let powerDurations: [Double] = [5, 15, 30, 60, 120, 300, 600, 1_200, 1_800, 3_600]
    public static let runningDistances: [Double] = [400, 1_000, 1_609.344, 5_000, 10_000, 21_097.5, 42_195]

    /// Power is held until the next recording, for at most 30 seconds.
    /// Every candidate has continuous coverage. Recorded zero power is valid.
    public static func powerCurve(_ samples: [Sample], durations: [Double] = powerDurations) throws -> [PowerEffort] {
        let runs = continuousRuns(samples) { $0.power.map { $0.isFinite && $0 >= 0 } == true }
        return try durations.map { seconds in
            guard seconds.isFinite, seconds > 0 else { return PowerEffort(seconds: seconds, watts: nil, start: nil) }
            var best: (watts: Double, start: Double)?
            for run in runs where run.count > 1 && run.last!.elapsed - run[0].elapsed >= seconds {
                try Task.checkCancellation()
                let times = run.map(\.elapsed)
                var energy = [0.0]
                for index in 0..<(run.count - 1) {
                    energy.append(energy.last! + run[index].power! * (times[index + 1] - times[index]))
                }
                func total(at time: Double) -> Double {
                    let index = min(times.count - 2, max(0, upperBound(times, value: time) - 1))
                    return energy[index] + run[index].power! * (time - times[index])
                }
                // An optimum begins or ends on a sample boundary.
                for (index, time) in times.enumerated() {
                    if index.isMultiple(of: 512) { try Task.checkCancellation() }
                    for start in [time, time - seconds] where start >= times[0] && start + seconds <= times.last! {
                        let watts = (total(at: start + seconds) - total(at: start)) / seconds
                        if best == nil || watts > best!.watts { best = (watts, start) }
                    }
                }
            }
            return PowerEffort(seconds: seconds, watts: best?.watts, start: best?.start)
        }
    }

    public static func bestDistanceEfforts(_ samples: [Sample], distances: [Double] = runningDistances) throws -> [DistanceEffort] {
        let runs = distanceRuns(samples)
        return try distances.map { meters in
            guard meters.isFinite, meters > 0 else { return DistanceEffort(meters: meters, seconds: nil, start: nil) }
            var best: (seconds: Double, start: Double)?
            for run in runs where run.last!.distance! - run[0].distance! >= meters {
                try Task.checkCancellation()
                let positions = run.map { $0.distance! }
                for (index, position) in positions.enumerated() {
                    if index.isMultiple(of: 512) { try Task.checkCancellation() }
                    for startDistance in [position, position - meters] where startDistance >= positions[0] && startDistance + meters <= positions.last! {
                        let start = time(at: startDistance, in: run, positions: positions, latest: true)
                        let seconds = time(at: startDistance + meters, in: run, positions: positions, latest: false) - start
                        if seconds > 0, best == nil || seconds < best!.seconds { best = (seconds, start) }
                    }
                }
            }
            return DistanceEffort(meters: meters, seconds: best?.seconds, start: best?.start)
        }
    }

    public static func runningSplits(_ samples: [Sample], length: Double = 1_000) -> [RunningSplit] {
        guard length.isFinite, length > 0, let last = samples.last?.distance, last.isFinite else { return [] }
        let runs = distanceRuns(samples)
        let count = min(1_000, Int(min(1_000, max(0, last / length)).rounded(.up)))
        return (0..<count).compactMap { index in
            let lower = Double(index) * length
            let upper = min(last, lower + length)
            guard upper > lower, let run = runs.first(where: { $0[0].distance! <= lower && $0.last!.distance! >= upper }) else { return nil }
            let distances = run.map { $0.distance! }
            let start = time(at: lower, in: run, positions: distances, latest: false)
            let end = time(at: upper, in: run, positions: distances, latest: false)
            let hr = Analysis.summary(samples, metric: .heartRate, start: start, end: end)
            return RunningSplit(number: index + 1, meters: upper - lower, start: start, end: end,
                                heartRate: hr.average, heartRateCoverage: hr.coveredSeconds / max(1, end - start))
        }
    }

    /// Drift compares speed / HR in equal elapsed halves, on jointly recorded time.
    public static func steadyEffort(_ samples: [Sample], start: Double, end: Double) -> SteadyEffort {
        guard end > start, start.isFinite, end.isFinite else {
            return SteadyEffort(averageSpeed: nil, averageHeartRate: nil, coverage: 0, driftPercent: nil, paceVariationPercent: nil)
        }
        let middle = (start + end) / 2
        func half(_ from: Double, _ to: Double) -> (speed: Double, hr: Double, coverage: Double, variation: Double) {
            var seconds = 0.0, speed = 0.0, hr = 0.0, squared = 0.0
            for (sample, next) in zip(samples, samples.dropFirst()) {
                let gap = next.elapsed - sample.elapsed
                guard gap > 0, gap <= 30, let s = sample.speed, s.isFinite, s > 0.5,
                      let h = sample.heartRate, h.isFinite, h > 0 else { continue }
                let duration = min(to, next.elapsed) - max(from, sample.elapsed)
                guard duration > 0 else { continue }
                seconds += duration
                speed += s * duration
                squared += s * s * duration
                hr += h * duration
            }
            guard seconds > 0 else { return (0, 0, 0, 0) }
            let average = speed / seconds
            return (average, hr / seconds, seconds / (to - from),
                    sqrt(max(0, squared / seconds - average * average)) / average * 100)
        }
        let first = half(start, middle), last = half(middle, end)
        let coverage = (first.coverage + last.coverage) / 2
        let drift = first.coverage >= 0.8 && last.coverage >= 0.8 && end - start >= 600 ?
            (1 - (last.speed / last.hr) / (first.speed / first.hr)) * 100 : nil
        let weight = first.coverage + last.coverage
        return SteadyEffort(averageSpeed: weight > 0 ? (first.speed * first.coverage + last.speed * last.coverage) / weight : nil,
                            averageHeartRate: weight > 0 ? (first.hr * first.coverage + last.hr * last.coverage) / weight : nil,
                            coverage: coverage, driftPercent: drift,
                            paceVariationPercent: weight > 0 ? (first.variation * first.coverage + last.variation * last.coverage) / weight : nil)
    }

    private static func distanceRuns(_ samples: [Sample]) -> [[Sample]] {
        continuousRuns(samples, additionalBreak: { $1.distance! < $0.distance! }) {
            $0.distance.map { $0.isFinite && $0 >= 0 } == true
        }.filter { $0.count > 1 }
    }

    private static func time(at distance: Double, in run: [Sample], positions: [Double], latest: Bool) -> Double {
        let upper = upperBound(positions, value: distance)
        if upper > 0, positions[upper - 1] == distance {
            let index = latest ? upper - 1 : upperBound(positions, value: distance.nextDown)
            return run[index].elapsed
        }
        let index = min(run.count - 2, max(0, upper - 1))
        let gap = positions[index + 1] - positions[index]
        guard gap > 0 else { return run[index].elapsed }
        return run[index].elapsed + (distance - positions[index]) / gap * (run[index + 1].elapsed - run[index].elapsed)
    }

    private static func continuousRuns(_ samples: [Sample], additionalBreak: (Sample, Sample) -> Bool = { _, _ in false },
                                       valid: (Sample) -> Bool) -> [[Sample]] {
        var result: [[Sample]] = [], current: [Sample] = []
        for sample in samples {
            guard sample.elapsed.isFinite, valid(sample) else {
                if !current.isEmpty { result.append(current); current = [] }
                continue
            }
            if let previous = current.last,
               sample.elapsed <= previous.elapsed || sample.elapsed - previous.elapsed > 30 || additionalBreak(previous, sample) {
                result.append(current)
                current = []
            }
            current.append(sample)
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    private static func upperBound(_ values: [Double], value: Double) -> Int {
        var lower = 0, upper = values.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if values[middle] <= value { lower = middle + 1 } else { upper = middle }
        }
        return lower
    }
}
