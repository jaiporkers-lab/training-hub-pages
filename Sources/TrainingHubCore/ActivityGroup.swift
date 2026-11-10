import Foundation

/// One original file is one feed activity; its sessions remain independently selectable.
public struct ActivityGroup: Identifiable, Sendable {
    public let sessions: [Activity]
    public let summary: Activity
    public var id: String { summary.id }
    public var isMultisport: Bool { sessions.count > 1 }
    public static let idPrefix = "activity:"

    init(sessions: [Activity]) {
        precondition(!sessions.isEmpty)
        let sorted = sessions.sorted {
            $0.start == $1.start ? $0.sessionIndex < $1.sessionIndex : $0.start < $1.start
        }
        self.sessions = sorted
        self.summary = Self.makeSummary(sorted)
    }

    public static func grouping(_ activities: [Activity]) -> [ActivityGroup] {
        Dictionary(grouping: activities, by: \.fileHash).values.map { ActivityGroup(sessions: $0) }
            .sorted { $0.summary.start == $1.summary.start ? $0.id < $1.id : $0.summary.start > $1.summary.start }
    }

    private static func makeSummary(_ sessions: [Activity]) -> Activity {
        var result = sessions[0]
        guard sessions.count > 1 else { return result }
        result.id = Self.idPrefix + result.fileHash
        result.sessionIndex = -1
        if let range = result.title.range(of: " · \(sessions[0].sessionIndex + 1). ", options: .backwards) {
            result.title = String(result.title[..<range.lowerBound])
        } else if let range = result.title.range(of: " · Session ", options: .backwards) {
            result.title = String(result.title[..<range.lowerBound])
        }
        let sports = Set(sessions.map(\.sport))
        result.sport = sports.isSuperset(of: ["swimming", "cycling", "running"]) ? "triathlon" : "multisport"
        result.subSport = "generic"
        result.start = sessions[0].start
        result.elapsed = sessions.map { $0.start.addingTimeInterval($0.elapsed) }.max()!.timeIntervalSince(result.start)
        result.timer = completeSum(sessions, \.timer)
        result.distance = completeSum(sessions, \.distance)
        result.ascent = completeSum(sessions, \.ascent)
        result.avgHeartRate = weightedAverage(sessions, \.avgHeartRate)
        result.avgPower = weightedAverage(sessions, \.avgPower)
        result.sampleCount = sessions.reduce(0) { $0 + $1.sampleCount }
        result.laps = sessions.flatMap(\.laps)
        result.isDemo = sessions.allSatisfy(\.isDemo)
        return result
    }

    public func legName(_ session: Activity) -> String {
        switch session.sport {
        case "swimming": return "Swim"
        case "cycling": return "Bike"
        case "running": return "Run"
        case "transition":
            let preceding = sessions.prefix { $0.id != session.id }.filter { $0.sport == "transition" }.count
            return "T\(preceding + 1)"
        default: return session.displaySport
        }
    }

    /// Half-open leg intervals assign exact boundaries to the following leg.
    /// Gaps and unknown distances remain unassigned, rather than borrowing a nearby sensor point.
    public func leg(at position: Double, distance: Bool = false) -> Activity? {
        guard position.isFinite, position >= 0 else { return nil }
        var offset = 0.0
        var spans: [(Activity, Double, Double)] = []
        for session in sessions {
            let start: Double
            let end: Double
            if distance {
                guard let length = session.distance, length.isFinite, length >= 0 else { break }
                start = offset; end = offset + length; offset = end
            } else {
                start = session.start.timeIntervalSince(sessions[0].start)
                end = start + session.elapsed
            }
            spans.append((session, start, end))
        }
        if let match = spans.reversed().first(where: { position >= $0.1 && position < $0.2 }) { return match.0 }
        if let last = spans.last, spans.count == sessions.count, position == last.2 { return last.0 }
        return nil
    }

    public func matches(search: String, sport: String) -> Bool {
        (sport == "All sports" || sport == summary.sport || sessions.contains { $0.sport == sport }) &&
        (search.isEmpty || summary.title.localizedCaseInsensitiveContains(search) ||
         summary.displaySport.localizedCaseInsensitiveContains(search) ||
         sessions.contains { $0.displaySport.localizedCaseInsensitiveContains(search) || legName($0).localizedCaseInsensitiveContains(search) })
    }

    /// A continuous race clock and cumulative distance; absent leg distance stays unknown.
    func combinedSamples(_ samplesBySession: [[Sample]]) -> [Sample] {
        let start = sessions[0].start
        var distanceOffset: Double? = 0
        var combined: [Sample] = []
        for (session, samples) in zip(sessions, samplesBySession) {
            for var sample in samples {
                sample.elapsed = sample.timestamp.timeIntervalSince(start)
                sample.distance = sample.distance.flatMap { distance in distanceOffset.map { $0 + distance } }
                combined.append(sample)
            }
            distanceOffset = distanceOffset.flatMap { offset in session.distance.map { offset + $0 } }
        }
        combined.sort { $0.timestamp < $1.timestamp }
        for index in combined.indices { combined[index].id = index }
        return combined
    }

    private static func completeSum(_ sessions: [Activity], _ value: (Activity) -> Double?) -> Double? {
        let values = sessions.compactMap(value)
        return values.count == sessions.count ? values.reduce(0, +) : nil
    }

    private static func weightedAverage(_ sessions: [Activity], _ value: (Activity) -> Double?) -> Double? {
        var total = 0.0
        var duration = 0.0
        for session in sessions {
            let weight = session.timer ?? session.elapsed
            guard weight > 0 else { continue }
            guard let average = value(session) else { return nil }
            total += average * weight
            duration += weight
        }
        return duration > 0 ? total / duration : nil
    }
}
