import Foundation

public enum CSVExport {
    public static func samples(_ samples: [Sample]) -> String {
        var rows = ["timestamp_utc,elapsed_seconds,distance_m,heart_rate_bpm,speed_m_s,power_w,cadence,altitude_m,temperature_c"]
        let formatter = ISO8601DateFormatter()
        for sample in samples {
            rows.append(([formatter.string(from: sample.timestamp), value(sample.elapsed)] +
                [sample.distance, sample.heartRate, sample.speed, sample.power, sample.cadence, sample.altitude, sample.temperature].map(value)).joined(separator: ","))
        }
        return rows.joined(separator: "\n") + "\n"
    }

    public static func laps(_ laps: [AnalysisLap]) -> String {
        let header = "leg,sport,lap,start_seconds,elapsed_seconds,timer_seconds,distance_m,average_speed_m_s\n"
        return header + laps.map { lap in
            ([escaped(lap.leg), escaped(lap.sport), String(lap.index)] +
             [lap.start, lap.elapsed, lap.timer, lap.distance, lap.averageSpeed].map(value)).joined(separator: ",")
        }.joined(separator: "\n") + "\n"
    }

    private static func value(_ number: Double?) -> String {
        guard let number, number.isFinite else { return "" }
        return String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), number)
    }
    private static func escaped(_ text: String) -> String {
        let text = text.first.map { "=+-@".contains($0) } == true ? "'" + text : text
        return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
