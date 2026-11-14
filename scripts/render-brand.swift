import AppKit
import CoreText
import ImageIO

let root = URL(fileURLWithPath: CommandLine.arguments[1])
let iconset = root.appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func renderIcon(pixels: Int, target: URL) {
    let size = 1024
    let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: pixels * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    context.setFillColor(CGColor(srgbRed: 17/255, green: 24/255, blue: 32/255, alpha: 1))
    context.addPath(CGPath(roundedRect: CGRect(x: 64, y: 64, width: 896, height: 896),
                           cornerWidth: 190, cornerHeight: 190, transform: nil))
    context.fillPath()
    let font = NSFont(name: "Arial-BoldMT", size: 400)!
    func line(_ text: String, color: NSColor) -> CTLine {
        CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color]))
    }
    let g = line("G", color: NSColor(srgbRed: 243/255, green: 246/255, blue: 251/255, alpha: 1))
    let h = line("H", color: NSColor(srgbRed: 9/255, green: 23/255, blue: 37/255, alpha: 1))
    let gBounds = CTLineGetBoundsWithOptions(g, .useGlyphPathBounds)
    let hBounds = CTLineGetBoundsWithOptions(h, .useGlyphPathBounds)
    let gap = 20.0, boxWidth = 356.0, boxHeight = 420.0
    let left = (Double(size) - gBounds.width - gap - boxWidth) / 2
    let box = CGRect(x: left + gBounds.width + gap, y: (Double(size) - boxHeight) / 2, width: boxWidth, height: boxHeight)
    context.setFillColor(CGColor(srgbRed: 22/255, green: 153/255, blue: 235/255, alpha: 1))
    context.addPath(CGPath(roundedRect: box, cornerWidth: 38, cornerHeight: 38, transform: nil))
    context.fillPath()
    let baseline = box.midY - hBounds.midY
    context.textPosition = CGPoint(x: left - gBounds.minX, y: baseline)
    CTLineDraw(g, context)
    context.textPosition = CGPoint(x: box.midX - hBounds.midX, y: baseline)
    CTLineDraw(h, context)
    let destination = CGImageDestinationCreateWithURL(target as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    precondition(CGImageDestinationFinalize(destination))
}

for size in [16, 32, 128, 256, 512] {
    renderIcon(pixels: size, target: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    renderIcon(pixels: size * 2, target: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
renderIcon(pixels: 1024, target: root.appendingPathComponent("AppIcon.png"))
renderIcon(pixels: 512, target: root.appendingPathComponent("GH-Logo.png"))
