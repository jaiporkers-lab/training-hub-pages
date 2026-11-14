import Foundation

public enum InsightTimeBasis: String, Hashable, Sendable { case elapsed, timer }

public struct InsightFact: Hashable, Identifiable, Sendable {
    public let id: String
    public let text: String
    public let sourceIDs: [String]
}

/// Immutable, app-authored evidence. Titles, notes, routes, samples and health never enter this packet.
public struct InsightEvidence: Hashable, Sendable {
    public let facts: [InsightFact]
    public let limitations: [String]
    public let timeBasis: InsightTimeBasis

    public var modelInput: String { facts.map { "\($0.id): \($0.text)" }.joined(separator: "\n") }

    public func selectedFacts(ids: [String]) throws -> [InsightFact] {
        guard (1...3).contains(ids.count), Set(ids).count == ids.count else { throw InsightEvidenceError.invalidSelection }
        return try ids.map { id in
            guard let fact = facts.first(where: { $0.id == id }) else { throw InsightEvidenceError.invalidSelection }
            return fact
        }
    }

    public static func comparison(selected: ActivityGroup, baseline: ActivityGroup, basis: InsightTimeBasis) -> Self {
        let legs = ActivityComparison.legs(selected: selected, baseline: baseline)
        var facts: [InsightFact] = []
        var limits = [
            "Only imported recordings are represented. Missing measurements are not zero.",
            "Less recorded time does not establish improved performance: routes and conditions may differ."
        ]
        func valid(_ value: Double?) -> Double? {
            value.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        }
        func number(_ value: Double, signed: Bool = false) -> String {
            String(format: signed ? "%+.1f" : "%.1f", locale: Locale(identifier: "en_US_POSIX"), value)
        }
        func time(_ activity: Activity?) -> Double? {
            guard let activity else { return nil }
            return valid(basis == .timer ? activity.timer : activity.elapsed)
        }
        let timeLabel = basis == .timer ? "Recorded timer" : "Elapsed time"
        func comparison(_ id: String, label: String, selected lhs: Double?, baseline rhs: Double?, unit: String, sources: [String]) {
            guard let lhs, let rhs, (lhs - rhs).isFinite else {
                facts.append(InsightFact(id: id, text: "\(label): comparison unavailable because a measurement is missing or invalid.", sourceIDs: sources))
                return
            }
            facts.append(InsightFact(id: id, text: "\(label): selected \(number(lhs)) \(unit), baseline \(number(rhs)) \(unit); selected minus baseline \(number(lhs - rhs, signed: true)) \(unit).", sourceIDs: sources))
        }
        let sources = [selected.summary.id, baseline.summary.id]
        comparison("overall.time", label: timeLabel, selected: time(selected.summary), baseline: time(baseline.summary), unit: "seconds", sources: sources)
        comparison("overall.distance", label: "Recorded distance", selected: valid(selected.summary.distance), baseline: valid(baseline.summary.distance), unit: "metres", sources: sources)
        if basis == .elapsed { limits.append("Elapsed time includes pauses; recorded timer is a separate measurement.") }
        if basis == .timer, time(selected.summary) == nil || time(baseline.summary) == nil {
            limits.append("Recorded timer is unavailable for at least one activity. Elapsed time has not been substituted.")
        }
        if let lhs = valid(selected.summary.distance), let rhs = valid(baseline.summary.distance), lhs != rhs {
            limits.append("Recorded distances differ, so this is not an equivalent-distance performance comparison.")
        }
        if valid(selected.summary.distance) == nil || valid(baseline.summary.distance) == nil {
            limits.append("Distance is unavailable for at least one activity.")
        }
        if selected.isMultisport || baseline.isMultisport {
            let unmatched = legs.filter { $0.selected == nil || $0.baseline == nil }.count
            limits.append("Legs are matched by sport and occurrence; \(unmatched) leg(s) have no counterpart.")
            for (index, leg) in legs.prefix(6).enumerated() {
                // Keep model text independent of activity titles and arbitrary FIT text fields.
                let label = "Leg \(index + 1) \(timeLabel.lowercased())"
                comparison("leg.\(index).time", label: label, selected: time(leg.selected), baseline: time(leg.baseline), unit: "seconds", sources: [leg.selected?.id, leg.baseline?.id].compactMap { $0 })
            }
            if legs.count > 6 { limits.append("Highlights cover the first six leg rows; the full comparison table includes all \(legs.count) legs.") }
        }
        return Self(facts: facts, limitations: limits, timeBasis: basis)
    }
}

public enum InsightEvidenceError: Error { case invalidSelection }
