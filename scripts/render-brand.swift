import Foundation
import CoreGraphics
import ImageIO

let root = URL(fileURLWithPath: CommandLine.arguments[1])
let iconset = root.appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let forest = CGColor(srgbRed: 18.0 / 255, green: 45.0 / 255, blue: 39.0 / 255, alpha: 1)
let lime = CGColor(srgbRed: 221.0 / 255, green: 249.0 / 255, blue: 144.0 / 255, alpha: 1)
let ink = CGColor(srgbRed: 185.0 / 255, green: 207.0 / 255, blue: 192.0 / 255, alpha: 1)

func pulse(_ context: CGContext, origin: CGPoint, scale: CGFloat) {
    let points: [CGPoint] = [
        .init(x: 1, y: 12), .init(x: 5, y: 12), .init(x: 8, y: 4), .init(x: 11, y: 13),
        .init(x: 14, y: 7), .init(x: 16, y: 12), .init(x: 20, y: 12)
    ]
    context.setStrokeColor(lime)
    context.setLineWidth(1.8 * scale)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.addLines(between: points.map { CGPoint(x: origin.x + $0.x * scale, y: origin.y + $0.y * scale) })
    context.strokePath()
}

func writePNG(size: Int, url: URL, tile: Bool) throws {
    guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
        bytesPerRow: size * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fatalError("Bitmap context") }
    context.translateBy(x: 0, y: CGFloat(size))
    context.scaleBy(x: CGFloat(size) / 1_024, y: -CGFloat(size) / 1_024)
    context.setFillColor(forest)
    if tile {
        let rect = CGRect(x: 64, y: 64, width: 896, height: 896)
        context.addPath(CGPath(roundedRect: rect, cornerWidth: 190, cornerHeight: 190, transform: nil))
        context.fillPath()
        pulse(context, origin: CGPoint(x: 199, y: 212), scale: 30)
        context.setFillColor(ink)
        // TH monogram under the pulse, with generous spacing at small sizes.
        for stroke in [
            CGRect(x: 408, y: 729, width: 90, height: 17),
            CGRect(x: 444, y: 729, width: 18, height: 75),
            CGRect(x: 529, y: 729, width: 18, height: 75),
            CGRect(x: 595, y: 729, width: 18, height: 75),
            CGRect(x: 529, y: 758, width: 84, height: 17)
        ] {
            context.fill(stroke)
        }
    } else {
        context.fillEllipse(in: CGRect(x: 0, y: 0, width: 1_024, height: 1_024))
        pulse(context, origin: CGPoint(x: 199, y: 255), scale: 30)
    }
    guard let image = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { fatalError("PNG destination") }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("PNG write") }
}

for size in [16, 32, 128, 256, 512] {
    try writePNG(size: size, url: iconset.appendingPathComponent("icon_\(size)x\(size).png"), tile: true)
    try writePNG(size: size * 2, url: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"), tile: true)
}
try writePNG(size: 1_024, url: root.appendingPathComponent("AppIcon.png"), tile: true)
try writePNG(size: 512, url: root.appendingPathComponent("TH-Logo.png"), tile: false)
