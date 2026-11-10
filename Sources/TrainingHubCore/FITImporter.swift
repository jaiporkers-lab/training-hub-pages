import Foundation
import Darwin
import CryptoKit
import FITSwiftSDK

public enum FITImporter {
    static let maximumFileSize = 100_000_000

    static func readFile(_ url: URL, limit: Int = maximumFileSize, prefixLength: Int? = nil) throws -> Data {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw HubError.message("Could not open the selected file. Choose a regular file.") }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG else {
            throw HubError.message("Choose a regular file.")
        }
        guard info.st_size <= limit else { throw HubError.message("The selected file exceeds the allowed size.") }
        if let prefixLength { return try handle.read(upToCount: min(prefixLength, limit)) ?? Data() }
        var data = Data()
        while let chunk = try handle.read(upToCount: min(1_048_576, limit - data.count + 1)), !chunk.isEmpty {
            guard chunk.count <= limit - data.count else { throw HubError.message("The selected file exceeds the allowed size.") }
            data.append(chunk)
        }
        return data
    }

    public static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public static func decode(_ data: Data, name: String, isDemo: Bool = false) throws -> [DecodedActivity] {
        guard data.count >= 14, data.count <= maximumFileSize else {
            throw HubError.message("Choose an uncompressed activity FIT file smaller than 100 MB.")
        }
        let decoder = FITSwiftSDK.Decoder(stream: FITSwiftSDK.InputStream(data: data))
        guard try decoder.isFIT(), try decoder.checkIntegrity() else {
            throw HubError.message("The file is incomplete or its FIT checksum is invalid. Export the original again.")
        }
        let listener = FitListener()
        decoder.addMesgListener(listener)
        try decoder.read()
        let messages = listener.fitMessages
        guard messages.fileIdMesgs.first?.getType() == .activity, !messages.sessionMesgs.isEmpty else {
            throw HubError.message("This FIT file is not a recorded activity with sessions.")
        }
        let fileHash = hash(data)
        let sessions = orderedSessions(messages.sessionMesgs)
        let spans = try sessions.enumerated().map { index, session in
            try sessionSpan(session, index: index)
        }
        let records = messages.recordMesgs.sorted {
            ($0.getTimestamp()?.timestamp ?? 0) < ($1.getTimestamp()?.timestamp ?? 0)
        }
        var transitionNumber = 0
        return sessions.enumerated().map { index, session in
            let span = spans[index]
            let start = span.start
            let nextStart = index + 1 < spans.count ? spans[index + 1].start : nil
            let selected = records.filter {
                guard let timestamp = $0.getTimestamp() else { return false }
                let time = date(timestamp)
                // Next-session ownership avoids duplicate boundary samples when rounded start
                // timestamps overlap a preceding leg's fractional elapsed duration.
                return time >= start && time <= span.end && (nextStart == nil || time < nextStart!)
            }
            // Session-relative distance makes overlays comparable even when a multisport device uses a cumulative counter.
            let distanceBase = selected.first?.getDistance() ?? 0
            let samples = selected.enumerated().compactMap { ordinal, record -> Sample? in
                guard let time = record.getTimestamp() else { return nil }
                return Sample(id: ordinal, timestamp: date(time), elapsed: date(time).timeIntervalSince(start),
                    distance: record.getDistance().map { max(0, $0 - distanceBase) },
                    heartRate: record.getHeartRate().map(Double.init),
                    speed: finite(record.getEnhancedSpeed() ?? record.getSpeed()), power: record.getPower().map(Double.init),
                    cadence: record.getCadence().map(Double.init), altitude: finite(record.getEnhancedAltitude() ?? record.getAltitude()),
                    temperature: record.getTemperature().map(Double.init),
                    latitude: record.getPositionLat().map { Double($0) * 180 / 2_147_483_648 },
                    longitude: record.getPositionLong().map { Double($0) * 180 / 2_147_483_648 })
            }
            let sport = session.getSport().map { String(describing: $0) } ?? "unknown"
            let subSport = session.getSubSport().map { String(describing: $0) } ?? "unknown"
            let laps = sessionLaps(session, all: messages.lapMesgs, span: span, nextStart: nextStart)
                .map { Lap(start: $0.getStartTime().map(date), elapsed: finite($0.getTotalElapsedTime()),
                        timer: finite($0.getTotalTimerTime()), distance: finite($0.getTotalDistance())) }
            if session.getSport() == .transition { transitionNumber += 1 }
            let legName: String
            switch session.getSport() {
            case .swimming: legName = "Swim"
            case .cycling: legName = "Bike"
            case .running: legName = "Run"
            case .transition: legName = "T\(transitionNumber)"
            default: legName = sport.capitalized
            }
            let activity = Activity(id: "\(fileHash):\(index)", fileHash: fileHash, sessionIndex: index,
                title: sessions.count == 1 ? name : "\(name) · \(index + 1). \(legName)", sport: sport, subSport: subSport,
                start: start, elapsed: span.elapsed, timer: finite(session.getTotalTimerTime()), distance: finite(session.getTotalDistance()),
                avgHeartRate: session.getAvgHeartRate().map(Double.init), avgPower: session.getAvgPower().map(Double.init),
                ascent: session.getTotalAscent().map(Double.init), sampleCount: samples.count, isDemo: isDemo, laps: laps)
            return DecodedActivity(activity: activity, samples: samples)
        }
    }

    static func orderedSessions(_ sessions: [SessionMesg]) -> [SessionMesg] {
        sessions.enumerated().sorted {
            let lhs = $0.element.getStartTime()?.timestamp ?? 0
            let rhs = $1.element.getStartTime()?.timestamp ?? 0
            return lhs == rhs ? $0.offset < $1.offset : lhs < rhs
        }.map(\.element)
    }

    struct SessionSpan {
        let start: Date
        let end: Date
        let elapsed: Double
    }

    static func sessionSpan(_ session: SessionMesg, index: Int) throws -> SessionSpan {
        guard let startFIT = session.getStartTime(), startFIT.timestamp != DateTime.invalid else {
            throw HubError.message("Session \(index + 1) has no usable start time. Its original FIT file is needed to identify this recording format.")
        }
        let start = date(startFIT)
        // Garmin defines summary spans as start_time + total_elapsed_time. A summary's
        // timestamp can be the race start, not its finish. Timer time excludes pauses.
        if let elapsed = finite(session.getTotalElapsedTime()), elapsed >= 0 {
            return SessionSpan(start: start, end: start.addingTimeInterval(elapsed), elapsed: elapsed)
        }
        // Older exports may omit elapsed duration. Use the summary timestamp only when
        // it actually provides a usable endpoint; never infer elapsed from timer time.
        if let endFIT = session.getTimestamp(), endFIT.timestamp != DateTime.invalid,
           endFIT.timestamp >= startFIT.timestamp {
            let end = date(endFIT)
            return SessionSpan(start: start, end: end, elapsed: end.timeIntervalSince(start))
        }
        throw HubError.message("Session \(index + 1) has neither an elapsed duration nor a usable finish time.")
    }

    private static func sessionLaps(_ session: SessionMesg, all: [LapMesg], span: SessionSpan, nextStart: Date?) -> [LapMesg] {
        if let first = session.getFirstLapIndex(), let count = session.getNumLaps() {
            let first = Int(first)
            let count = Int(count)
            // Laps belong to sessions by their explicit index range when available.
            // This also handles stationary transitions without GPS/record messages.
            let indexed = all.filter { lap in
                guard let messageIndex = lap.getMessageIndex() else { return false }
                let index = Int(messageIndex & 0x0fff) // FIT message_index reserves the upper bits.
                return index >= first && index < first + count
            }
            if indexed.count == count { return indexed }
            if all.allSatisfy({ $0.getMessageIndex() == nil }), first + count <= all.count {
                return Array(all[first..<first + count])
            }
        }
        return all.filter { lap in
            guard let startFIT = lap.getStartTime() else { return false }
            let time = date(startFIT)
            return time >= span.start && time < span.end && (nextStart == nil || time < nextStart!)
        }
    }

    static func date(_ value: DateTime) -> Date {
        Date(timeIntervalSince1970: Double(value.timestamp) + 631_065_600)
    }
    private static func finite(_ value: Double?) -> Double? { value.flatMap { $0.isFinite ? $0 : nil } }
}
