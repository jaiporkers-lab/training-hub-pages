import Foundation
import CoreFoundation

public enum HealthSource: String, Codable, CaseIterable, Sendable {
    case daily, sleep, hrv, weight
    public var title: String {
        switch self { case .daily: "Daily wellness"; case .sleep: "Sleep"; case .hrv: "HRV"; case .weight: "Weight" }
    }
}
public struct HealthMetric: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let unit: String
    public let source: HealthSource
    let path: String
    let scale: Double
    let positive: Bool
    init(_ id: String, _ title: String, _ unit: String, _ source: HealthSource, _ path: String, scale: Double = 1, positive: Bool = false) {
        self.id = id; self.title = title; self.unit = unit; self.source = source; self.path = path; self.scale = scale; self.positive = positive
    }
    public static let all: [Self] = [
        .init("rhr", "Resting heart rate", "bpm", .daily, "heartRate.restingValue", positive: true),
        .init("hrMin", "Minimum daily heart rate", "bpm", .daily, "heartRate.minValue", positive: true),
        .init("hrMax", "Maximum daily heart rate", "bpm", .daily, "heartRate.maxValue", positive: true),
        .init("steps", "Steps", "steps", .daily, "movement.steps.value"),
        .init("floors", "Floors climbed", "floors", .daily, "movement.floorsAscended.value"),
        .init("stress", "Average stress", "points", .daily, "stress.avgLevel"),
        .init("bbHigh", "Body Battery high", "points", .daily, "bodyBattery.maxValue", positive: true),
        .init("bbLow", "Body Battery low", "points", .daily, "bodyBattery.minValue", positive: true),
        .init("bbEnd", "Body Battery before sleep", "points", .daily, "bodyBattery.endOfDayValue", positive: true),
        .init("water", "Hydration logged", "L", .daily, "hydration.consumedInFractionalMl", scale: 0.001),
        .init("respiration", "Average respiration", "breaths/min", .daily, "respiration.avgValue", positive: true),
        .init("spo2", "Average pulse oximetry", "%", .daily, "pulseOx.avgValue", positive: true),
        .init("activeCalories", "Active calories", "kcal", .daily, "calories.burnedActive"),
        .init("totalCalories", "Total calories", "kcal", .daily, "calories.burnedTotal"),
        .init("moderate", "Moderate intensity", "min", .daily, "intensityMinutes.moderate"),
        .init("vigorous", "Vigorous intensity", "min", .daily, "intensityMinutes.vigorous"),
        .init("sleep", "Sleep duration", "hours", .sleep, "sleepTimeSeconds", scale: 1 / 3_600),
        .init("deep", "Deep sleep", "hours", .sleep, "deepSleepSeconds", scale: 1 / 3_600),
        .init("rem", "REM sleep", "hours", .sleep, "remSleepSeconds", scale: 1 / 3_600),
        .init("light", "Light sleep", "hours", .sleep, "lightSleepSeconds", scale: 1 / 3_600),
        .init("awake", "Awake during sleep", "hours", .sleep, "awakeSleepSeconds", scale: 1 / 3_600),
        .init("sleepHR", "Average sleeping heart rate", "bpm", .sleep, "avgHeartRate", positive: true),
        .init("sleepScore", "Sleep score", "points", .sleep, "sleepScores.overall.value"),
        .init("hrv", "Overnight HRV", "ms", .hrv, "lastNightAvg", positive: true),
        .init("hrvWeekly", "Garmin 7-day HRV average", "ms", .hrv, "weeklyAvg", positive: true),
        .init("weight", "Latest daily weight", "kg", .weight, "latestWeight.weight", positive: true),
        .init("bmi", "Latest daily BMI", "BMI", .weight, "latestWeight.bmi", positive: true),
        .init("bodyFat", "Latest daily body fat", "%", .weight, "latestWeight.bodyFat", positive: true)
    ]
}

public struct HealthDay: Codable, Identifiable, Sendable {
    public var id: String { source.rawValue + ":" + day }
    public let day: String
    public let source: HealthSource
    public let values: [String: Double]
    public init(day: String, source: HealthSource, values: [String: Double]) { self.day = day; self.source = source; self.values = values }
}
public struct HealthCache: Codable, Sendable {
    public var days: [HealthDay] = []
    public var updated: Date?
    public init() {}
}
public struct HealthComparison: Sendable {
    public let current: Double?
    public let previous: Double?
    public let currentCount: Int
    public let previousCount: Int
}

public enum HealthAnalysis {
    public static func formatter() -> DateFormatter {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian); formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
        return formatter
    }
    public static func date(_ day: String) -> Date? {
        let formatter = formatter()
        guard let date = formatter.date(from: day), formatter.string(from: date) == day else { return nil }
        return date
    }
    public static func decode(_ data: Data, source: HealthSource) throws -> [HealthDay] {
        guard !data.isEmpty else { return [] }
        let object = try JSONSerialization.jsonObject(with: data)
        let rows: [[String: Any]]
        if source == .sleep, let array = object as? [[String: Any]] { rows = array }
        else if let root = object as? [String: Any], let array = root[source == .daily ? "data" : source == .hrv ? "hrvSummaries" : "dailyWeightSummaries"] as? [[String: Any]] { rows = array }
        else { throw HubError.message("Garmin returned an unsupported \(source.title) response format.") }
        return rows.compactMap { row in
            guard let day = row[source == .weight ? "summaryDate" : "calendarDate"] as? String, date(day) != nil else { return nil }
            var values: [String: Double] = [:]
            for metric in HealthMetric.all where metric.source == source {
                var current: Any? = row
                for key in metric.path.split(separator: ".") { current = (current as? [String: Any])?[String(key)] }
                guard let number = current as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { continue }
                let value = number.doubleValue * metric.scale
                guard value.isFinite, value >= 0, !metric.positive || value > 0 else { continue }
                values[metric.id] = value
            }
            return HealthDay(day: day, source: source, values: values)
        }
    }
    /// Compare completed local calendar days; missing values never become zero.
    public static func compare(_ records: [HealthDay], metric: HealthMetric, days: Int, now: Date = Date()) -> HealthComparison {
        let today = Calendar.current.startOfDay(for: now)
        let start = Calendar.current.date(byAdding: .day, value: -days, to: today)!
        let previous = Calendar.current.date(byAdding: .day, value: -days, to: start)!
        let f = formatter(); let endKey = f.string(from: today), startKey = f.string(from: start), previousKey = f.string(from: previous)
        func values(_ from: String, _ to: String) -> [Double] {
            records.filter { $0.source == metric.source && $0.day >= from && $0.day < to }.compactMap { $0.values[metric.id] }
        }
        let current = values(startKey, endKey), old = values(previousKey, startKey)
        return HealthComparison(current: current.isEmpty ? nil : current.reduce(0, +) / Double(current.count),
                                previous: old.isEmpty ? nil : old.reduce(0, +) / Double(old.count), currentCount: current.count, previousCount: old.count)
    }
}

extension ActivityStore {
    public func healthCache() throws -> HealthCache {
        guard let json = try syncValue("health.cache.v1") else { return HealthCache() }
        return try JSONDecoder().decode(HealthCache.self, from: Data(json.utf8))
    }
    public func saveHealth(_ records: [HealthDay], source: HealthSource, from: String, to: String) throws {
        var cache = try healthCache()
        cache.days.removeAll { $0.source == source && $0.day >= from && $0.day <= to }
        cache.days += records.filter { $0.source == source && $0.day >= from && $0.day <= to }
        cache.days = Dictionary(grouping: cache.days, by: \.id).values.compactMap(\.last).sorted { $0.id < $1.id }
        cache.updated = Date()
        let data = try JSONEncoder().encode(cache)
        try setSyncValue("health.cache.v1", String(decoding: data, as: UTF8.self))
    }
}

extension GarminClient {
    public func health(apiKey: String, source: HealthSource, from: String, to: String) async throws -> [HealthDay] {
        guard let start = HealthAnalysis.date(from), let end = HealthAnalysis.date(to), start <= end,
              Calendar.current.dateComponents([.day], from: start, to: end).day! < 31 else {
            throw HubError.message("Health requests must cover at most 31 calendar days.")
        }
        let path: String
        switch source {
        case .daily: path = "/usersummary-service/v2/dailysummaries"
        case .sleep: path = "/sleep-service/sleep/dailySleepSummariesByDate"
        case .hrv: path = "/hrv-service/hrv/daily/\(from)/\(to)"
        case .weight: path = "/weight-service/weight/range/\(from)/\(to)"
        }
        var url = URLComponents(string: "https://personal.connectapi.garmin.com" + path)!
        if source == .daily || source == .sleep { url.queryItems = [URLQueryItem(name: "startDate", value: from), URLQueryItem(name: "endDate", value: to)] }
        let response = try await authorized(apiKey: apiKey, url: url.url!, accept: "application/json")
        return try HealthAnalysis.decode(response.data, source: source)
    }
}
