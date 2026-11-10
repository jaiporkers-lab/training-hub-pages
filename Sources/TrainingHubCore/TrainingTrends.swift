import Foundation

public struct TrendTotals: Sendable {
    public var activities = 0
    public var seconds = 0.0
    public var meters = 0.0
    public var missingDistances = 0
    public var elapsedFallbacks = 0
    mutating func add(_ sessions: [Activity]) {
        guard !sessions.isEmpty else { return }
        activities += 1
        for session in sessions {
            seconds += session.timer ?? session.elapsed
            if session.timer == nil { elapsedFallbacks += 1 }
            if let distance = session.distance { meters += distance }
            else { missingDistances += 1 }
        }
    }
}

public struct TrendWeek: Identifiable, Sendable {
    public var id: Date { start }
    public let start: Date
    public let current: TrendTotals
    public let previous: TrendTotals
}
public struct TrendSport: Identifiable, Sendable {
    public var id: String { sport }
    public let sport: String
    public let totals: TrendTotals
}
public struct TrainingTrends: Sendable {
    public let start: Date
    public let end: Date
    public let previousStart: Date
    public let previousEnd: Date
    public let current: TrendTotals
    public let previous: TrendTotals
    public let weeks: [TrendWeek]
    public let sports: [TrendSport]

    public static func make(activities: [Activity], weeks requestedWeeks: Int = 4, sport: String? = nil,
                            includeDemo: Bool = false, now: Date = Date(), calendar input: Calendar = .current) -> Self {
        var calendar = input
        calendar.firstWeekday = 2; calendar.minimumDaysInFirstWeek = 4
        let count = min(52, max(1, requestedWeeks))
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)!.start
        let start = calendar.date(byAdding: .weekOfYear, value: -(count - 1), to: thisWeek)!
        let previousStart = calendar.date(byAdding: .weekOfYear, value: -count, to: start)!
        let previousEnd = calendar.date(byAdding: .weekOfYear, value: -count, to: now)!
        // Callers may supply feed selections containing a synthetic whole-race row.
        let originals = activities.filter { $0.sessionIndex >= 0 && (includeDemo || !$0.isDemo) }
        let groups = ActivityGroup.grouping(Array(Dictionary(grouping: originals, by: \.id).values.compactMap(\.first)))
        func totals(from: Date, to: Date) -> TrendTotals {
            var result = TrendTotals()
            for group in groups where group.sessions[0].start >= from && group.sessions[0].start < to {
                result.add(group.sessions.filter { sport == nil || $0.sport == sport })
            }
            return result
        }
        let buckets = (0..<count).map { index -> TrendWeek in
            let from = calendar.date(byAdding: .weekOfYear, value: index, to: start)!
            let to = min(now, calendar.date(byAdding: .weekOfYear, value: 1, to: from)!)
            let oldFrom = calendar.date(byAdding: .weekOfYear, value: -count, to: from)!
            let oldTo = calendar.date(byAdding: .weekOfYear, value: -count, to: to)!
            return TrendWeek(start: from, current: totals(from: from, to: to), previous: totals(from: oldFrom, to: oldTo))
        }
        let currentGroups = groups.filter { $0.sessions[0].start >= start && $0.sessions[0].start < now }
        let sports = Set(currentGroups.flatMap(\.sessions).map(\.sport)).sorted().filter { sport == nil || $0 == sport }.map { name in
            var result = TrendTotals()
            for group in currentGroups { result.add(group.sessions.filter { $0.sport == name }) }
            return TrendSport(sport: name, totals: result)
        }
        return Self(start: start, end: now, previousStart: previousStart, previousEnd: previousEnd,
                    current: totals(from: start, to: now), previous: totals(from: previousStart, to: previousEnd), weeks: buckets, sports: sports)
    }
}
