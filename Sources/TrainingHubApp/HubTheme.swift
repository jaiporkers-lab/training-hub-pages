import AppKit
import SwiftUI

enum HubTheme {
    static let background = adaptive(0xf5f7fa, 0x10151e)
    static let sidebar = adaptive(0xecf0f5, 0x151c27)
    static let surface = adaptive(0xffffff, 0x1a2330)
    static let ink = adaptive(0x142034, 0xeff4fc)
    static let muted = adaptive(0x526477, 0xa9b8cc)
    static let line = adaptive(0xd4dde8, 0x344254)
    static let accent = adaptive(0x0876bd, 0x60bcfa)
    static let selected = adaptive(0x0876bd, 0x168fdc)
    static let selectedInk = adaptive(0xffffff, 0xffffff)
    static let accentWash = adaptive(0xe0effa, 0x18354c)

    static let boardBackground = color(0x101c2c)
    static let plotPrimary = color(0x57b8f7)
    static let boardText = color(0xf0f5fc)
    static let boardMuted = color(0xa9bcd2)
    static let boardLine = color(0x3a506b)
    static let boardRaised = color(0x21364e)
    static let comparison = color(0xf2b769)

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
        .background(HubTheme.boardBackground, in: RoundedRectangle(cornerRadius: 15))
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
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            HStack(spacing: size * 0.025) {
                Text("G").foregroundStyle(Color.white)
                Text("H")
                    .foregroundStyle(Color(red: 9 / 255, green: 23 / 255, blue: 37 / 255))
                    .frame(width: size * 0.40, height: size * 0.51)
                    .background(Color(red: 22 / 255, green: 153 / 255, blue: 235 / 255),
                                in: RoundedRectangle(cornerRadius: size * 0.05))
            }
            .font(.custom("Arial-BoldMT", size: size * 0.46))
            .frame(width: size, height: size)
            .background(Color(red: 17 / 255, green: 24 / 255, blue: 32 / 255),
                        in: RoundedRectangle(cornerRadius: size * 0.22))
        }.accessibilityHidden(true)
    }
}

struct GarHubWordmark: View {
    var body: some View {
        HStack(spacing: 1) {
            Text("Gar").foregroundStyle(HubTheme.ink)
            Text("Hub")
                .foregroundStyle(Color(red: 9 / 255, green: 23 / 255, blue: 37 / 255))
                .padding(.horizontal, 4).padding(.vertical, 2)
                .background(Color(red: 22 / 255, green: 153 / 255, blue: 235 / 255),
                            in: RoundedRectangle(cornerRadius: 4))
        }.font(.custom("Arial-BoldMT", size: 25)).tracking(-0.8)
            .accessibilityLabel("GarHub")
    }
}

enum HubAppearance: String, CaseIterable {
    case system = "Match Mac"
    case paper = "Paper"
    case dark = "Dark"

    var title: String { self == .paper ? "Light" : rawValue }

    var scheme: ColorScheme? {
        switch self {
        case .system: nil
        case .paper: .light
        case .dark: .dark
        }
    }
}
