import Foundation
import FITSwiftSDK

public struct PoolSwim: Sendable {
    public let lengthMeters: Double?
    public let lengths: [SwimLength]
}

public struct SwimLength: Identifiable, Sendable {
    public enum Kind: String, Sendable { case swim = "Swim", rest = "Rest", unknown = "Unspecified" }

    public let id: Int
    public let startOffset: TimeInterval
    public let kind: Kind
    public let timer: TimeInterval?
    public let elapsed: TimeInterval?
    public let strokes: Int?
    public let stroke: String?

    public var swolf: Int? {
        guard kind == .swim, let timer, timer > 0, let strokes, strokes > 0 else { return nil }
        return Int(timer.rounded()) + strokes
    }

    public func pacePer100Meters(poolLength: Double?) -> Double? {
        guard kind == .swim, let timer, timer > 0, let poolLength, poolLength > 0 else { return nil }
        return timer / poolLength * 100
    }
}

extension FITImporter {
    public static func poolSwim(_ data: Data, sessionIndex: Int) throws -> PoolSwim? {
        guard data.count >= 14, data.count <= maximumFileSize else { throw HubError.message("The original FIT file has an unsupported size.") }
        let decoder = FITSwiftSDK.Decoder(stream: FITSwiftSDK.InputStream(data: data))
        guard try decoder.isFIT(), try decoder.checkIntegrity() else { throw HubError.message("The original FIT file failed its integrity check.") }
        let listener = SwimListener()
        decoder.addMesgListener(listener)
        try decoder.read()
        let sessions = orderedSessions(listener.sessions)
        guard sessions.indices.contains(sessionIndex), sessions[sessionIndex].getSport() == .swimming else { return nil }
        let session = sessions[sessionIndex]
        let span = try sessionSpan(session, index: sessionIndex)
        let nextStart = sessions.dropFirst(sessionIndex + 1).first?.getStartTime().map(date)
        let rows = listener.lengths.enumerated().compactMap { ordinal, length -> SwimLength? in
            guard let timestamp = length.getStartTime(), timestamp.timestamp != DateTime.invalid else { return nil }
            let start = date(timestamp)
            guard start >= span.start, start < (nextStart ?? .distantFuture), start < span.end else { return nil }
            let kind: SwimLength.Kind = switch length.getLengthType() {
            case .active: .swim
            case .idle: .rest
            default: .unknown
            }
            let stroke: String? = switch length.getSwimStroke() {
            case .freestyle: "Freestyle"
            case .backstroke: "Backstroke"
            case .breaststroke: "Breaststroke"
            case .butterfly: "Butterfly"
            case .drill: "Drill"
            case .mixed: "Mixed"
            case .im, .imByRound, .rimo: "Medley"
            default: nil
            }
            return SwimLength(id: ordinal, startOffset: start.timeIntervalSince(span.start), kind: kind,
                timer: validDuration(length.getTotalTimerTime()), elapsed: validDuration(length.getTotalElapsedTime()),
                strokes: length.getTotalStrokes().map(Int.init), stroke: stroke)
        }.sorted { $0.startOffset == $1.startOffset ? $0.id < $1.id : $0.startOffset < $1.startOffset }
        guard !rows.isEmpty else { return nil }
        return PoolSwim(lengthMeters: session.getPoolLength().flatMap { $0.isFinite && $0 > 0 ? $0 : nil }, lengths: rows)
    }

    private static func validDuration(_ value: Double?) -> Double? {
        // FIT's timer and elapsed fields are uint32 millisecond counters.
        value.flatMap { $0.isFinite && $0 >= 0 && $0 <= Double(UInt32.max) / 1_000 ? $0 : nil }
    }
}

private final class SwimListener: MesgListener {
    var sessions: [SessionMesg] = []
    var lengths: [LengthMesg] = []

    func onMesg(_ mesg: Mesg) {
        switch mesg.mesgNum {
        case Profile.MesgNum.session: sessions.append(SessionMesg(mesg: mesg))
        case Profile.MesgNum.length: lengths.append(LengthMesg(mesg: mesg))
        default: break
        }
    }
}

extension ActivityStore {
    public func poolSwim(fileHash: String, sessionIndex: Int) throws -> PoolSwim? {
        try FITImporter.poolSwim(originalRecording(fileHash: fileHash), sessionIndex: sessionIndex)
    }
}
