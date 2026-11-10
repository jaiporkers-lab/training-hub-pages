import CoreGraphics
import FITSwiftSDK
import Foundation

extension ActivityGroup {
    /// Multisport recordings can have both indoor and outdoor legs.
    public func outdoorRouteSessions(sport: String? = nil) -> [Activity] {
        sessions.filter { session in
            session.isOutdoorRouteCandidate && (sport == nil || session.sport == sport || summary.sport == sport)
        }
    }
}

extension Activity {
    public var isOutdoorRouteCandidate: Bool {
        guard !isDemo, sport != "fitnessEquipment" else { return false }
        let subtype = subSport.lowercased()
        return !subtype.hasPrefix("indoor") && !subtype.hasPrefix("virtual") &&
            !["treadmill", "spin", "lapswimming", "elliptical", "stairclimbing", "esport"].contains(subtype)
    }
}

public struct RouteHeatmap: Sendable {
    struct Chunk: Sendable {
        let points: [CGPoint]
        let bounds: CGRect
    }

    /// Coordinates are in a unit Web Mercator world, with y increasing south.
    /// Longitude bounds may extend past 1 to keep a date-line route together.
    public let bounds: CGRect?
    let activities: [[Chunk]]
    private let inspection: RouteInspectionIndex
    public var activityCount: Int { activities.count }

    /// Finds each recording once within a radius in unit Web Mercator coordinates.
    public func activityIDs(near point: CGPoint, radius: Double) -> [String] {
        inspection.activityIDs(near: point, radius: radius)
    }

    public func activityCount(near point: CGPoint, radius: Double) -> Int {
        inspection.activityCount(near: point, radius: radius)
    }

    private init(bounds: CGRect?, activities: [[Chunk]], ids: [String?]) {
        self.bounds = bounds
        self.activities = activities
        inspection = RouteInspectionIndex(activities: activities, ids: ids)
    }

    public struct Builder {
        private var activities: [[Chunk]] = []
        private var ids: [String?] = []
        private var current: [Chunk] = []

        public init() {}

        public mutating func addSession(_ samples: [Sample], trimStart: Bool = false, trimEnd: Bool = false) throws {
            var runs: [[Fix]] = []
            var run: [Fix] = []
            for (index, sample) in samples.enumerated() {
                if index.isMultiple(of: 512) { try Task.checkCancellation() }
                guard let latitude = sample.latitude, let longitude = sample.longitude,
                      (-85.05112878...85.05112878).contains(latitude),
                      (-180...180).contains(longitude) else {
                    if !run.isEmpty {
                        runs.append(run)
                        run = []
                    }
                    continue
                }
                let radians = latitude * .pi / 180
                let x = (longitude + 180) / 360
                let y = (1 - asinh(tan(radians)) / .pi) / 2
                var point = CGPoint(x: x, y: y)
                if let last = run.last {
                    let offset = x - last.point.x
                    point.x = last.point.x + offset - offset.rounded()
                    let elapsed = sample.timestamp.timeIntervalSince(last.time)
                    let metres = hypot(point.x - last.point.x, y - last.point.y) * 40_075_017 * cos(radians)
                    if elapsed <= 0 || elapsed > 30 || metres > min(600, max(30, elapsed * 45)) {
                        runs.append(run)
                        run = []
                        point.x = x
                    }
                }
                run.append(Fix(point: point, time: sample.timestamp, distance: sample.distance, speed: sample.speed))
            }
            if !run.isEmpty { runs.append(run) }
            // Keep the full route if the data is too sparse to establish movement.
            guard !runs.isEmpty else { return }
            var start = (run: 0, fix: 0)
            var end = (run: runs.count - 1, fix: runs[runs.count - 1].count - 1)
            let movingStart = trimStart ? try movingEdge(in: runs, fromEnd: false) : nil
            let movingEnd = trimEnd ? try movingEdge(in: runs, fromEnd: true) : nil
            if (movingStart ?? start) <= (movingEnd ?? end) {
                start = movingStart ?? start
                end = movingEnd ?? end
            }
            for index in start.run...end.run {
                try Task.checkCancellation()
                let fixes = runs[index]
                let lower = index == start.run ? start.fix : 0
                let upper = index == end.run ? end.fix : fixes.count - 1
                var points: [CGPoint] = []
                for fix in fixes[lower...upper] where points.last != fix.point { points.append(fix.point) }
                finishRun(points)
            }
        }

        private struct Fix {
            let point: CGPoint
            let time: Date
            let distance: Double?
            let speed: Double?

            func separation(from other: Fix) -> Double {
                let latitudeScale = 1 / cosh(.pi * (1 - point.y - other.point.y))
                return hypot(point.x - other.point.x, point.y - other.point.y) * 40_075_017 * latitudeScale
            }

            func distanceChange(from other: Fix) -> Double? {
                guard let distance, let previous = other.distance, distance.isFinite, previous.isFinite else { return nil }
                return abs(distance - previous)
            }
        }

        private func movingEdge(in runs: [[Fix]], fromEnd: Bool) throws -> (run: Int, fix: Int)? {
            let step = fromEnd ? -1 : 1
            for runIndex in stride(from: fromEnd ? runs.count - 1 : 0, to: fromEnd ? -1 : runs.count, by: step) {
                let fixes = runs[runIndex]
                let first = fromEnd ? fixes.count - 1 : 0
                let limit = fromEnd ? -1 : fixes.count
                var anchor = first
                for index in stride(from: first + step, to: limit, by: step) {
                    if index.isMultiple(of: 512) { try Task.checkCancellation() }
                    let previous = index - step
                    let fix = fixes[index]
                    let pair = fixes[previous]
                    let advance = fix.distanceChange(from: pair) ?? 0
                    let speed = max(fix.speed ?? 0, pair.speed ?? 0)
                    let separation = fix.separation(from: pair)
                    if (advance >= 2 && separation >= 1) || (speed >= 0.8 && separation >= 2) {
                        return (runIndex, previous)
                    }
                    // Older files can lack speed or distance. Require a larger GPS
                    // displacement and avoid interpreting drift as movement when the
                    // device reports both a stopped speed and a flat distance counter.
                    while anchor != previous && abs(fix.time.timeIntervalSince(fixes[anchor].time)) > 12 { anchor += step }
                    let origin = fixes[anchor]
                    let stopped = (fix.distanceChange(from: origin) ?? .infinity) < 2 &&
                        fix.speed.map { $0 < 0.5 } == true && origin.speed.map { $0 < 0.5 } == true
                    if !stopped && fix.separation(from: origin) >= 12 {
                        let departure = stride(from: previous, through: anchor, by: -step)
                            .first { fixes[$0].separation(from: origin) <= 3 }
                        return (runIndex, departure ?? anchor)
                    }
                }
            }
            return nil
        }

        public mutating func finishActivity(id: String? = nil) {
            guard !current.isEmpty else { return }
            activities.append(current)
            ids.append(id)
            current = []
        }

        public func makeHeatmap() -> RouteHeatmap {
            var columns: [Double] = []
            var north = Double.infinity
            var south = -Double.infinity
            for activity in activities {
                for chunk in activity {
                    north = min(north, chunk.bounds.minY)
                    south = max(south, chunk.bounds.maxY)
                    columns.append(contentsOf: chunk.points.map { $0.x - floor($0.x) })
                }
            }
            columns.sort()
            guard let first = columns.first, let last = columns.last else {
                return RouteHeatmap(bounds: nil, activities: [], ids: [])
            }
            var gap = first + 1 - last
            var west = first
            var east = last
            for (left, right) in zip(columns, columns.dropFirst()) where right - left > gap {
                gap = right - left
                west = right
                east = left + 1
            }
            return RouteHeatmap(bounds: CGRect(x: west, y: north, width: east - west, height: south - north),
                                activities: activities, ids: ids)
        }

        private mutating func finishRun(_ run: [CGPoint]) {
            guard !run.isEmpty else { return }
            // A tile only visits nearby chunks. Neighbouring chunks share the edge endpoint.
            for offset in stride(from: 0, to: max(1, run.count - 1), by: 96) {
                let points = Array(run[offset..<min(offset + 97, run.count)])
                let xs = points.map(\.x), ys = points.map(\.y)
                guard let west = xs.min(), let east = xs.max(), let north = ys.min(), let south = ys.max() else { continue }
                current.append(Chunk(points: points, bounds: CGRect(x: west, y: north, width: east - west, height: south - north)))
            }
        }
    }
}

extension ActivityStore {
    public func routeHeatmap(groups: [ActivityGroup], sport: String?, trimIdle: Bool = true) async throws -> RouteHeatmap {
        var builder = RouteHeatmap.Builder()
        for group in groups where !group.summary.isDemo {
            try Task.checkCancellation()
            let sessions = group.outdoorRouteSessions(sport: sport)
            guard !sessions.isEmpty, !hasVirtualFITCreator(fileHash: group.summary.fileHash) else { continue }
            for session in sessions {
                try builder.addSession(samples(for: session.id), trimStart: trimIdle && session.id == group.sessions.first?.id,
                                       trimEnd: trimIdle && session.id == group.sessions.last?.id)
            }
            builder.finishActivity(id: group.id)
            await Task.yield()
        }
        return builder.makeHeatmap()
    }

    private func hasVirtualFITCreator(fileHash: String) -> Bool {
        guard Self.validHash(fileHash),
              let prefix = try? FITImporter.readFile(root.appendingPathComponent("Originals/\(fileHash).fit"), prefixLength: 4_096),
              !prefix.isEmpty else { return false }
        let decoder = FITSwiftSDK.Decoder(stream: FITSwiftSDK.InputStream(data: prefix))
        let listener = RouteFITCreator()
        decoder.addMesgListener(listener)
        // The creator is in the first FIT message. Stop the SDK there so building
        // the map never decodes every archived file a second time.
        try? decoder.read()
        return listener.isVirtual
    }
}

private final class RouteFITCreator: MesgListener {
    private enum Stop: Error { case firstMessageRead }
    private(set) var isVirtual = false

    func onMesg(_ mesg: Mesg) throws {
        if mesg.mesgNum == MesgNum.fileId.rawValue {
            let file = FileIdMesg(mesg: mesg)
            switch file.getManufacturer() {
            case .tacx, .zwift, .zwiftByte, .bkool, .trainerRoad, .theSufferfest, .virtualtraining, .virtugo,
                 .rGTCycling, .ictrainer, .mywhoosh, .peloton:
                isVirtual = true
            case .garmin:
                if let id = file.getProduct(), let product = GarminProduct(rawValue: id) {
                    let name = String(describing: product)
                    isVirtual = name.hasPrefix("tacx") || name.hasPrefix("trainingPeaksVirtual")
                }
            default:
                break
            }
        }
        throw Stop.firstMessageRead
    }
}
