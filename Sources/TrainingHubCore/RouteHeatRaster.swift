import CoreGraphics
import Foundation

public enum RouteHeatRaster {
    public struct Ink: Sendable {
        public let red: Double
        public let green: Double
        public let blue: Double
        public let opacity: Double
    }

    private static let stops: [(density: Double, ink: Ink)] = [
        (0, Ink(red: 0.27, green: 0.13, blue: 0.79, opacity: 0)),
        (0.2, Ink(red: 0.47, green: 0.24, blue: 0.97, opacity: 0.39)),
        (1, Ink(red: 0.73, green: 0.33, blue: 1, opacity: 0.91)),
        (2, Ink(red: 0.99, green: 0.24, blue: 0.62, opacity: 0.98)),
        (4, Ink(red: 1, green: 0.47, blue: 0.21, opacity: 1)),
        (7, Ink(red: 1, green: 0.77, blue: 0.25, opacity: 1)),
        (10, Ink(red: 1, green: 0.98, blue: 0.77, opacity: 1))
    ]

    // The accumulated field uses 255 as the weight of one route's centreline.
    private static let maximumDensity: UInt16 = 2_550
    private static let palette = (0...Int(maximumDensity)).map { value -> [UInt8] in
        let ink = ink(at: Double(value) / 255)
        return [ink.red * ink.opacity, ink.green * ink.opacity, ink.blue * ink.opacity, ink.opacity]
            .map { UInt8(($0 * 255).rounded()) }
    }

    public static func ink(at density: Double) -> Ink {
        guard let upper = stops.firstIndex(where: { $0.density >= density }) else { return stops[stops.count - 1].ink }
        guard upper > 0 else { return stops[0].ink }
        let left = stops[upper - 1], right = stops[upper]
        let fraction = (density - left.density) / (right.density - left.density)
        func mix(_ a: Double, _ b: Double) -> Double { a + (b - a) * fraction }
        return Ink(red: mix(left.ink.red, right.ink.red), green: mix(left.ink.green, right.ink.green),
                   blue: mix(left.ink.blue, right.ink.blue), opacity: mix(left.ink.opacity, right.ink.opacity))
    }

    public static func image(_ heatmap: RouteHeatmap, viewport: CGRect, width: Int, height: Int, radius: Double) -> CGImage? {
        guard let field = density(heatmap, viewport: viewport, width: width, height: height, radius: radius) else { return nil }
        var pixels = Data(count: field.count * 4)
        pixels.withUnsafeMutableBytes { (bytes: UnsafeMutableRawBufferPointer) in
            for index in field.indices where field[index] > 0 {
                let color = palette[Int(field[index])]
                let offset = index * 4
                bytes[offset] = color[0]
                bytes[offset + 1] = color[1]
                bytes[offset + 2] = color[2]
                bytes[offset + 3] = color[3]
            }
        }
        guard let provider = CGDataProvider(data: pixels as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    static func density(_ heatmap: RouteHeatmap, viewport: CGRect, width: Int, height: Int, radius: Double) -> [UInt16]? {
        guard (1...1_600).contains(width), (1...1_600).contains(height),
              viewport.width > 0, viewport.height > 0, radius.isFinite, radius > 0 else { return nil }
        let sx = Double(width) / viewport.width
        let sy = Double(height) / viewport.height
        let padded = viewport.insetBy(dx: -radius / sx, dy: -radius / sy)
        let paths = heatmap.activities.compactMap { activity -> [CGPath]? in
            let strokes = strokes(for: activity, viewport: viewport, padded: padded, sx: sx, sy: sy, height: height)
            return strokes.isEmpty ? nil : strokes
        }
        guard !paths.isEmpty else { return nil }

        let bytesPerRow = (width + 15) & ~15
        var mask = [UInt8](repeating: 0, count: bytesPerRow * height)
        var field = [UInt16](repeating: 0, count: width * height)
        let area = CGRect(x: 0, y: 0, width: width, height: height)
        let kernel: [(fraction: Double, weight: Double)] = [
            (1, 0.025), (0.86, 0.055), (0.73, 0.11), (0.61, 0.20),
            (0.49, 0.34), (0.37, 0.55), (0.25, 0.78), (0.15, 1)
        ]

        return mask.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
            context.setLineJoin(.round)
            context.setLineCap(.round)
            context.setFillColor(gray: 0, alpha: 1)
            for activity in paths {
                if Task.isCancelled { return nil }
                context.fill(area)
                // Painting small paths separately avoids the expensive intersection
                // work of stroking thousands of overlapping edges in a single path.
                for (fraction, weight) in kernel {
                    context.setStrokeColor(gray: weight, alpha: 1)
                    context.setLineWidth(2 * radius * fraction)
                    for stroke in activity {
                        context.addPath(stroke)
                        context.strokePath()
                    }
                }
                let footprint = activity.reduce(CGRect.null) { $0.union($1.boundingBoxOfPath) }
                    .insetBy(dx: -radius - 1, dy: -radius - 1).intersection(area).integral
                if footprint.isNull || footprint.isEmpty { continue }
                let rows = (height - Int(footprint.maxY))..<(height - Int(footprint.minY))
                let columns = Int(footprint.minX)..<Int(footprint.maxX)
                for row in rows {
                    let source = row * bytesPerRow
                    let target = row * width
                    for column in columns where bytes[source + column] > 0 {
                        let index = target + column
                        field[index] = min(maximumDensity, field[index] + UInt16(bytes[source + column]))
                    }
                }
            }
            return field
        }
    }

    private static func strokes(for chunks: [RouteHeatmap.Chunk], viewport: CGRect, padded: CGRect,
                                sx: Double, sy: Double, height: Int) -> [CGPath] {
        var strokes: [CGPath] = []
        for chunk in chunks where chunk.bounds.maxY >= padded.minY && chunk.bounds.minY <= padded.maxY {
            let nearestWorld = (viewport.midX - chunk.bounds.midX).rounded()
            for offset in [-1.0, 0, 1] {
                let shift = nearestWorld + offset
                guard chunk.bounds.maxX + shift >= padded.minX, chunk.bounds.minX + shift <= padded.maxX else { continue }
                let path = CGMutablePath()
                var last: CGPoint?
                for (index, point) in chunk.points.enumerated() {
                    let pixel = CGPoint(x: (point.x + shift - viewport.minX) * sx, y: Double(height) - (point.y - viewport.minY) * sy)
                    if let last {
                        if index != chunk.points.count - 1 && abs(pixel.x - last.x) < 0.55 && abs(pixel.y - last.y) < 0.55 { continue }
                        path.addLine(to: pixel)
                    } else {
                        path.move(to: pixel)
                        if chunk.points.count == 1 { path.addLine(to: CGPoint(x: pixel.x + 0.01, y: pixel.y)) }
                    }
                    last = pixel
                }
                if !path.isEmpty { strokes.append(path) }
            }
        }
        return strokes
    }
}
