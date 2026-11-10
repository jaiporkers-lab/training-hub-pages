import SwiftUI
import Charts

/// The only view invalidated by pointer movement. The underlying Chart owns no
/// hover/selection state and never recreates its marks for an inspection update.
struct ChartInspectionOverlay<Value: Plottable, Readout: View>: View {
    let proxy: ChartProxy
    let reset: String
    let readout: (Value) -> Readout
    @State private var hovered: CGPoint?
    @State private var pinned: CGPoint?

    init(proxy: ChartProxy, reset: String, @ViewBuilder readout: @escaping (Value) -> Readout) {
        self.proxy = proxy; self.reset = reset; self.readout = readout
    }

    var body: some View {
        GeometryReader { geometry in
            if let anchor = proxy.plotFrame {
                let frame = geometry[anchor]
                ZStack(alignment: .topLeading) {
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let point): updateHover(point, frame: frame)
                            case .ended: hovered = nil
                            }
                        }
                        .gesture(DragGesture(minimumDistance: 0)
                            .onChanged { event in if frame.contains(event.location) { pinned = event.location; hovered = event.location } }
                            .onEnded { event in if frame.contains(event.location) { pinned = event.location } })
                    if let point = hovered ?? pinned, let value: Value = proxy.value(atX: point.x - frame.minX) {
                        Path { path in
                            path.move(to: CGPoint(x: point.x, y: frame.minY))
                            path.addLine(to: CGPoint(x: point.x, y: frame.maxY))
                        }.stroke(HubTheme.boardMuted.opacity(0.8), lineWidth: 1).allowsHitTesting(false)
                        let width = min(216.0, max(100, frame.width - 16))
                        let origin = max(frame.minX + 4, min(point.x + 12, frame.maxX - width - 4))
                        VStack(alignment: .leading, spacing: 4) { readout(value) }
                            .font(.caption).padding(10).frame(width: width, alignment: .leading)
                            .foregroundStyle(HubTheme.boardText)
                            .background(HubTheme.boardRaised, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(HubTheme.boardLine))
                            .offset(x: origin, y: frame.minY + 6)
                            .allowsHitTesting(false)
                    }
                    if pinned != nil {
                        Button("Clear inspection") { pinned = nil; hovered = nil }
                            .buttonStyle(.bordered).controlSize(.mini).accessibilityLabel("Clear inspection")
                            .position(x: frame.maxX - 55, y: frame.maxY - 14)
                    }
                }
                .transaction { $0.animation = nil }
            }
        }
        .onChange(of: reset) { hovered = nil; pinned = nil }
    }
    private func updateHover(_ point: CGPoint, frame: CGRect) {
        guard frame.contains(point) else { if hovered != nil { hovered = nil }; return }
        if let previous = hovered, abs(previous.x - point.x) < 0.5 && abs(previous.y - point.y) < 0.5 { return }
        hovered = point
    }
}
