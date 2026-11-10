import AppKit
import SwiftUI

enum HubTheme {
    static let paper = adaptive(0xf6f5ec, 0x121e1a)
    static let sidebar = adaptive(0xeeefe5, 0x17241f)
    static let surface = adaptive(0xfffef7, 0x1d2d26)
    static let ink = adaptive(0x172522, 0xf1f5e9)
    static let muted = adaptive(0x52625b, 0xb0c3b7)
    static let line = adaptive(0xd4d9ce, 0x3b5147)
    static let accent = adaptive(0x305c46, 0xddf990)
    static let selected = adaptive(0x122d27, 0xddf990)
    static let selectedInk = adaptive(0xfffef7, 0x172522)
    static let accentWash = adaptive(0xe3ebd9, 0x2c473a)

    static let forest = color(0x122d27)
    static let lime = color(0xddf990)
    static let boardText = color(0xfffef7)
    static let boardMuted = color(0xb9cfc0)
    static let boardLine = color(0x527166)
    static let boardRaised = color(0x26473b)
    static let comparison = color(0xf5bc8e)

    private static func color(_ rgb: UInt32) -> Color { Color(nsColor: nsColor(rgb)) }

    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            nsColor(appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light)
        })
    }

    private static func nsColor(_ rgb: UInt32) -> NSColor {
        NSColor(srgbRed: Double((rgb >> 16) & 255) / 255,
                green: Double((rgb >> 8) & 255) / 255,
                blue: Double(rgb & 255) / 255, alpha: 1)
    }
}

extension View {
    func hubPanel(padding: CGFloat = 16) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14)
        return self.padding(padding)
            .background(HubTheme.surface, in: shape)
            .overlay(shape.strokeBorder(HubTheme.line).allowsHitTesting(false))
    }

    func hubHeading(size: CGFloat = 28) -> some View {
        font(.system(size: size, weight: .bold))
            .tracking(-size * 0.035)
            .foregroundStyle(HubTheme.ink)
            .accessibilityAddTraits(.isHeader)
    }
}

struct HubEyebrow: View {
    let title: String
    let color: Color

    init(_ title: String, color: Color = HubTheme.muted) {
        self.title = title
        self.color = color
    }

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .tracking(1.1)
            .foregroundStyle(color)
    }
}

struct HubChartBoard<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HubEyebrow(subtitle, color: HubTheme.boardMuted)
                Text(title).font(.title3.bold()).accessibilityAddTraits(.isHeader)
            }
            content
                .environment(\.colorScheme, .dark)
        }
        .foregroundStyle(HubTheme.boardText)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HubTheme.forest, in: RoundedRectangle(cornerRadius: 15))
    }
}

struct HubPillStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(selected ? .semibold : .medium))
            .foregroundStyle(selected ? HubTheme.selectedInk : HubTheme.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(selected ? HubTheme.selected : HubTheme.surface, in: RoundedRectangle(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(selected ? HubTheme.selected : HubTheme.line)
            }
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}

struct HubBrandMark: View {
    var body: some View {
        Circle().fill(HubTheme.forest)
            .overlay {
                GeometryReader { geometry in
                    let scale = geometry.size.width / 36
                    Path { path in
                        let pulse: [CGPoint] = [
                            .init(x: 8, y: 22), .init(x: 12, y: 22), .init(x: 15, y: 14),
                            .init(x: 18, y: 23), .init(x: 21, y: 17), .init(x: 23, y: 22), .init(x: 27, y: 22)
                        ]
                        path.addLines(pulse.map { CGPoint(x: $0.x * scale, y: $0.y * scale) })
                    }.stroke(HubTheme.lime, style: StrokeStyle(lineWidth: 1.8 * scale, lineCap: .round, lineJoin: .round))
                }
            }
            .accessibilityHidden(true)
    }
}

enum HubAppearance: String, CaseIterable {
    case system = "Match Mac"
    case paper = "Paper"
    case dark = "Dark"

    var scheme: ColorScheme? {
        switch self {
        case .system: nil
        case .paper: .light
        case .dark: .dark
        }
    }
}
