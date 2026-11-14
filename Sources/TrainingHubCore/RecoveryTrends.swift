import Foundation

public struct RecoveryPoint: Identifiable, Sendable {
    public var id: Date { date }
    public let date: Date
    public let trainingMinutes: Double
    public let activities: Int
    public let health: Double?
    public let rollingAverage: Double?
    public let rollingDays: Int
}

public struct RecoveryTrends: Sendable {
    public let points: [RecoveryPoint]
    public let recentMean: Double?
    public let previousMean: Double?
    public let recentDays: Int
    public let previousDays: Int
    public let association: Double?
    public let pairs: Int

    public static func make(activities: [Activity], health: [HealthDay], metric: HealthMetric,
                            days: Int, lag: Int = 0, now: Date = Date(), calendar: Calendar = .current) -> Self {
        let today = calendar.startOfDay(for: now)
        let count = min(365, max(7, days))
        let start = calendar.date(byAdding: .day, value: -count, to: today)!
        let formatter = HealthAnalysis.formatter()
        formatter.timeZone = calendar.timeZone
        let values = Dictionary(health.filter { $0.source == metric.source }.compactMap { day -> (String, Double)? in
            guard let value = day.values[metric.id], value.isFinite else { return nil }
            return (day.day, value)
        }, uniquingKeysWith: { _, last in last })
        let originals = activities.filter { !$0.isDemo && $0.sessionIndex >= 0 }
        let groups = ActivityGroup.grouping(Array(Dictionary(grouping: originals, by: \.id).values.compactMap(\.first)))
        let byDay = Dictionary(grouping: groups) { formatter.string(from: $0.summary.start) }
        let points = (0..<count).map { offset -> RecoveryPoint in
            let date = calendar.date(byAdding: .day, value: offset, to: start)!
            let day = formatter.string(from: date)
            let sessions = byDay[day] ?? []
            let minutes = sessions.flatMap(\.sessions).reduce(0) { $0 + ($1.timer ?? $1.elapsed) } / 60
            let rolling = (0..<7).compactMap { ago in
                calendar.date(byAdding: .day, value: -ago, to: date).flatMap { values[formatter.string(from: $0)] }
            }
            return RecoveryPoint(date: date, trainingMinutes: minutes, activities: sessions.count,
                                 health: values[day], rollingAverage: mean(rolling), rollingDays: rolling.count)
        }
        let recentStart = calendar.date(byAdding: .day, value: -7, to: today)!
        let baselineStart = calendar.date(byAdding: .day, value: -35, to: today)!
        func measurements(from: Date, to: Date) -> [Double] {
            let lower = formatter.string(from: from), upper = formatter.string(from: to)
            return values.filter { $0.key >= lower && $0.key < upper }.map(\.value)
        }
        let recent = measurements(from: recentStart, to: today)
        let previous = measurements(from: baselineStart, to: recentStart)
        let pairs = points.compactMap { point -> (Double, Double)? in
            guard let day = calendar.date(byAdding: .day, value: min(1, max(0, lag)), to: point.date),
                  day < today, let value = values[formatter.string(from: day)] else { return nil }
            return (point.trainingMinutes, value)
        }
        var correlation: Double?
        if pairs.count >= 10 {
            let x = pairs.map(\.0), y = pairs.map(\.1)
            let mx = mean(x)!, my = mean(y)!
            let numerator = pairs.reduce(0) { $0 + ($1.0 - mx) * ($1.1 - my) }
            let denominator = sqrt(x.reduce(0) { $0 + pow($1 - mx, 2) } * y.reduce(0) { $0 + pow($1 - my, 2) })
            if denominator > 0 { correlation = max(-1, min(1, numerator / denominator)) }
        }
        return Self(points: points, recentMean: mean(recent), previousMean: mean(previous), recentDays: recent.count,
                    previousDays: previous.count, association: correlation, pairs: pairs.count)
    }

    private static func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }
}
