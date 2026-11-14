import Foundation

public struct TrainingPlan: Codable, Identifiable, Equatable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable { case workout = "Workout", race = "Race" }
    public let id: String
    public var title: String
    public var date: Date
    public var sport: String
    public var minutes: Double
    public var kind: Kind

    public init(id: String = UUID().uuidString, title: String, date: Date, sport: String, minutes: Double, kind: Kind) {
        self.id = id
        self.title = title
        self.date = date
        self.sport = sport
        self.minutes = minutes
        self.kind = kind
    }

    public static func decode(_ json: String) throws -> [Self] {
        let plans = try JSONDecoder().decode([Self].self, from: Data(json.utf8))
        guard plans.count <= 2_000, Set(plans.map(\.id)).count == plans.count,
              plans.allSatisfy({ !$0.id.isEmpty && $0.id.count <= 100 && !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                  $0.title.count <= 120 && $0.date.timeIntervalSince1970.isFinite && $0.minutes.isFinite &&
                  (0...10_080).contains($0.minutes) && $0.sport.count <= 60 }) else {
            throw HubError.message("The saved calendar contains an unsupported entry.")
        }
        return plans.sorted { $0.date < $1.date }
    }

    public static func encode(_ plans: [Self]) throws -> String {
        let json = String(decoding: try JSONEncoder().encode(plans), as: UTF8.self)
        _ = try decode(json)
        return json
    }

    public func moved(to day: Date, calendar: Calendar = .current) -> Self {
        let time = calendar.dateComponents([.hour, .minute], from: date)
        var copy = self
        copy.date = calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: 0, of: day) ?? day
        return copy
    }
}

public struct DashboardLayout: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public var name: String
    public var sport: String
    public var training: Bool
    public var health: Bool
    public var recent: Bool
    public var goal: Bool

    public init(id: String = UUID().uuidString, name: String, sport: String = "", training: Bool = true,
                health: Bool = true, recent: Bool = true, goal: Bool = true) {
        self.id = id
        self.name = name
        self.sport = sport
        self.training = training
        self.health = health
        self.recent = recent
        self.goal = goal
    }

    public static var builtins: [Self] {
        [Self(id: "all", name: "All activities"),
         Self(id: "triathlon", name: "Triathlon", health: false),
         Self(id: "running", name: "Running", sport: "running"),
         Self(id: "cycling", name: "Cycling", sport: "cycling"),
         Self(id: "swimming", name: "Swimming", sport: "swimming"),
         Self(id: "recovery", name: "Recovery", recent: false, goal: false)]
    }
}

public struct PersonalBest: Identifiable, Sendable {
    public var id: Double { target }
    public let target: Double
    public let value: Double
    public let activityID: String
    public let date: Date
    public let title: String
    public let start: Double
}

extension ActivityStore {
    public func personalBests(sport: String, activities: [Activity],
                              progress: @Sendable (Int, Int) async -> Void) async throws -> [PersonalBest] {
        let originals = activities.filter { !$0.isDemo && $0.sessionIndex >= 0 && $0.sport == sport }
        let eligible = Array(Dictionary(grouping: originals, by: \.id).values.compactMap(\.first))
            .sorted { $0.start < $1.start }
        var records: [Double: PersonalBest] = [:]
        for (index, activity) in eligible.enumerated() {
            try Task.checkCancellation()
            let data = try samples(for: activity.id)
            let efforts: [(Double, Double?, Double?)]
            if sport == "cycling" {
                efforts = try PerformanceAnalysis.powerCurve(data).map { ($0.seconds, $0.watts, $0.start) }
            } else {
                efforts = try PerformanceAnalysis.bestDistanceEfforts(data).map { ($0.meters, $0.seconds, $0.start) }
            }
            for (target, value, start) in efforts {
                guard let value, let start else { continue }
                let previous = records[target]?.value
                let better = previous == nil || (sport == "cycling" ? value > previous! : value < previous!)
                if better {
                    records[target] = PersonalBest(target: target, value: value, activityID: activity.id, date: activity.start,
                                                   title: activity.title, start: start)
                }
            }
            if index.isMultiple(of: 8) || index == eligible.count - 1 { await progress(index + 1, eligible.count) }
            await Task.yield()
        }
        return records.values.sorted { $0.target < $1.target }
    }
}
