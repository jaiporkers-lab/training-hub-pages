import Foundation

public struct ComparisonLeg: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let selected: Activity?
    public let baseline: Activity?
    public var elapsedDifference: Double? { difference(selected?.elapsed, baseline?.elapsed) }
    public var timerDifference: Double? { difference(selected?.timer, baseline?.timer) }
    public var distanceDifference: Double? { difference(selected?.distance, baseline?.distance) }
    private func difference(_ lhs: Double?, _ rhs: Double?) -> Double? {
        guard let lhs, let rhs, lhs.isFinite, rhs.isFinite else { return nil }
        return lhs - rhs
    }
}

public enum ActivityComparison {
    /// Match repeated sports by occurrence, preserving gaps rather than shifting later legs.
    public static func legs(selected: ActivityGroup, baseline: ActivityGroup) -> [ComparisonLeg] {
        func keyed(_ group: ActivityGroup) -> [(String, String, Activity)] {
            var seen: [String: Int] = [:]
            let counts = Dictionary(grouping: group.sessions, by: \.sport).mapValues(\.count)
            return group.sessions.map { session in
                let ordinal = seen[session.sport, default: 0]
                seen[session.sport] = ordinal + 1
                let suffix = session.sport != "transition" && counts[session.sport, default: 0] > 1 ? " \(ordinal + 1)" : ""
                return ("\(session.sport):\(ordinal)", group.legName(session) + suffix, session)
            }
        }
        let left = keyed(selected), right = keyed(baseline)
        let keys = left.map { $0.0 } + right.filter { item in !left.contains { $0.0 == item.0 } }.map { $0.0 }
        return keys.map { key in
            let lhs = left.first { $0.0 == key }, rhs = right.first { $0.0 == key }
            return ComparisonLeg(id: key, title: lhs?.1 ?? rhs!.1, selected: lhs?.2, baseline: rhs?.2)
        }
    }
}
