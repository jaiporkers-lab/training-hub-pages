import Foundation
import TrainingHubCore

func sportSymbol(_ sport: String) -> String {
    switch sport {
    case "triathlon", "multisport": "figure.mixed.cardio"
    case "running": "figure.run"
    case "walking", "hiking": "figure.walk"
    case "swimming": "figure.pool.swim"
    case "cycling": "figure.outdoor.cycle"
    case "transition": "arrow.triangle.swap"
    case "rowing": "figure.rower"
    case "strengthTraining", "training": "dumbbell"
    default: "figure.mixed.cardio"
    }
}

func activityMenuTitle(_ activity: Activity) -> String {
    "\(activity.start.formatted(date: .abbreviated, time: .shortened)) · \(activity.title) · \(distance(activity.distance))"
}

func formattedHealthValue(_ value: Double?, metric: HealthMetric) -> String {
    guard let value else { return "Not recorded" }
    if ["sleep", "deep", "rem", "light", "awake"].contains(metric.id) {
        let minutes = Int((value * 60).rounded())
        return "\(minutes / 60)h \(minutes % 60)m"
    }
    if ["steps", "floors", "activeCalories", "totalCalories"].contains(metric.id) {
        return "\(value.formatted(.number.precision(.fractionLength(0)))) \(metric.unit)"
    }
    return String(format: "%.1f %@", value, metric.unit)
}

func readableFieldName(_ name: String) -> String {
    name.replacingOccurrences(of: "([A-Z])([A-Z][a-z])", with: "$1 $2", options: .regularExpression)
        .replacingOccurrences(of: "([a-z0-9])([A-Z])", with: "$1 $2", options: .regularExpression)
        .replacingOccurrences(of: "_", with: " ")
        .replacingOccurrences(of: "^Avg ", with: "Average ", options: .regularExpression)
        .replacingOccurrences(of: "^Max ", with: "Maximum ", options: .regularExpression)
        .replacingOccurrences(of: "^Min ", with: "Minimum ", options: .regularExpression)
}
