import Foundation

public enum WelcomeReason: Equatable {
    case firstLaunch
    case updated
    case returning

    public static func resolve(currentRelease: String, previousRelease: String?, hasUsedEarlierVersion: Bool,
                               lastUse: Date?, now: Date, calendar: Calendar = .current) -> Self? {
        if previousRelease == nil && !hasUsedEarlierVersion { return .firstLaunch }
        if previousRelease != currentRelease { return .updated }
        guard let lastUse, let cutoff = calendar.date(byAdding: .month, value: -3, to: now),
              lastUse < cutoff else { return nil }
        return .returning
    }
}
