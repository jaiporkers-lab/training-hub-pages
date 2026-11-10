import CoreGraphics

struct RouteInspectionIndex: Sendable {
    private let root: Node?
    private let ids: [String?]

    init(activities: [[RouteHeatmap.Chunk]], ids: [String?]) {
        self.ids = ids
        let entries = zip(activities.indices, activities).flatMap { index, chunks in
            ids[index] == nil ? [] : chunks.map { Entry(chunk: $0, activity: index) }
        }
        root = entries.isEmpty ? nil : Node(entries)
    }

    func activityIDs(near point: CGPoint, radius: Double) -> [String] {
        matches(near: point, radius: radius).sorted().compactMap { ids[$0] }
    }

    func activityCount(near point: CGPoint, radius: Double) -> Int {
        matches(near: point, radius: radius).count
    }

    private func matches(near point: CGPoint, radius: Double) -> Set<Int> {
        guard let root, point.x.isFinite, point.y.isFinite, radius.isFinite, radius > 0 else { return [] }
        let x = point.x - floor(point.x)
        var found: Set<Int> = []
        for wrappedX in [x, x - 1, x + 1] {
            root.collect(near: CGPoint(x: wrappedX, y: point.y), radius: radius, into: &found)
        }
        return found
    }

    private struct Entry: Sendable {
        let chunk: RouteHeatmap.Chunk
        let activity: Int
        let offset: Double
        let bounds: CGRect

        init(chunk: RouteHeatmap.Chunk, activity: Int) {
            self.chunk = chunk
            self.activity = activity
            offset = floor(chunk.bounds.midX)
            bounds = chunk.bounds.offsetBy(dx: -offset, dy: 0)
        }

        func hits(_ point: CGPoint, radius: Double) -> Bool {
            let cursor = CGPoint(x: point.x + offset, y: point.y)
            let radiusSquared = radius * radius
            guard let first = chunk.points.first else { return false }
            var previous = first
            for next in chunk.points.dropFirst() {
                let dx = next.x - previous.x, dy = next.y - previous.y
                let lengthSquared = dx * dx + dy * dy
                let projection = lengthSquared > 0 ?
                    ((cursor.x - previous.x) * dx + (cursor.y - previous.y) * dy) / lengthSquared : 0
                let fraction = min(1, max(0, projection))
                let x = cursor.x - (previous.x + dx * fraction)
                let y = cursor.y - (previous.y + dy * fraction)
                if x * x + y * y <= radiusSquared { return true }
                previous = next
            }
            if chunk.points.count == 1 {
                let dx = cursor.x - first.x, dy = cursor.y - first.y
                return dx * dx + dy * dy <= radiusSquared
            }
            return false
        }
    }

    private struct Node: Sendable {
        private indirect enum Contents: Sendable {
            case entries([Entry])
            case children(Node, Node)
        }

        let bounds: CGRect
        private let contents: Contents

        init(_ entries: [Entry]) {
            bounds = entries.reduce(.null) { $0.union($1.bounds) }
            if entries.count <= 8 {
                contents = .entries(entries)
            } else {
                let horizontal = bounds.width >= bounds.height
                let sorted = entries.sorted {
                    horizontal ? $0.bounds.midX < $1.bounds.midX : $0.bounds.midY < $1.bounds.midY
                }
                let middle = sorted.count / 2
                contents = .children(Node(Array(sorted[..<middle])), Node(Array(sorted[middle...])))
            }
        }

        func collect(near point: CGPoint, radius: Double, into found: inout Set<Int>) {
            guard Self.isNear(bounds, point: point, radius: radius) else { return }
            switch contents {
            case .children(let left, let right):
                left.collect(near: point, radius: radius, into: &found)
                right.collect(near: point, radius: radius, into: &found)
            case .entries(let entries):
                for entry in entries where !found.contains(entry.activity) {
                    if Self.isNear(entry.bounds, point: point, radius: radius), entry.hits(point, radius: radius) {
                        found.insert(entry.activity)
                    }
                }
            }
        }

        private static func isNear(_ bounds: CGRect, point: CGPoint, radius: Double) -> Bool {
            abs(point.x - bounds.midX) <= bounds.width / 2 + radius &&
                abs(point.y - bounds.midY) <= bounds.height / 2 + radius
        }
    }
}
