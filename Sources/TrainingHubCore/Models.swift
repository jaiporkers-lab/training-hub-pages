import Foundation

public struct Sample: Codable, Identifiable, Sendable {
    public var id: Int
    public var timestamp: Date
    public var elapsed: Double
    public var distance: Double?
    public var heartRate: Double?
    public var speed: Double?
    public var power: Double?
    public var cadence: Double?
    public var altitude: Double?
    public var temperature: Double?
    public var latitude: Double?
    public var longitude: Double?
}

public struct Lap: Codable, Sendable {
    public var start: Date?
    public var elapsed: Double?
    public var timer: Double?
    public var distance: Double?
}

public struct Activity: Codable, Identifiable, Sendable, Hashable {
    public var id: String
    public var fileHash: String
    public var sessionIndex: Int
    public var title: String
    public var sport: String
    public var subSport: String
    public var start: Date
    public var elapsed: Double
    public var timer: Double?
    public var distance: Double?
    public var avgHeartRate: Double?
    public var avgPower: Double?
    public var ascent: Double?
    public var sampleCount: Int
    public var isDemo: Bool
    public var laps: [Lap]

    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
    public var displaySport: String {
        let base = sport.prefix(1).uppercased() + sport.dropFirst()
        return subSport == "generic" || subSport == "unknown" ? base : "\(base) · \(subSport)"
    }
}

public struct DecodedActivity: Sendable {
    public var activity: Activity
    public var samples: [Sample]
}

public enum Metric: String, CaseIterable, Identifiable, Sendable {
    case heartRate = "Heart rate", speed = "Speed", pace = "Pace", power = "Power", cadence = "Cadence", altitude = "Elevation", temperature = "Temperature"
    public var id: String { rawValue }
    public var unit: String {
        switch self {
        case .heartRate: "bpm"
        case .speed: "km/h"
        case .pace: "min/km"
        case .power: "W"
        case .cadence: "rpm / spm"
        case .altitude: "m"
        case .temperature: "°C"
        }
    }
    public func value(_ sample: Sample) -> Double? {
        switch self {
        case .heartRate: sample.heartRate
        case .speed: sample.speed.map { $0 * 3.6 }
        case .pace: sample.speed.flatMap { $0 > 0 && $0.isFinite ? 1_000 / $0 / 60 : nil }
        case .power: sample.power
        case .cadence: sample.cadence
        case .altitude: sample.altitude
        case .temperature: sample.temperature
        }
    }
}

public enum HubError: LocalizedError {
    case message(String)
    public var errorDescription: String? {
        switch self { case .message(let text): text }
    }
}
