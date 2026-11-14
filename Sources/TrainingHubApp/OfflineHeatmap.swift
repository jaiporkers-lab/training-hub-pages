import SwiftUI
import TrainingHubCore

struct OfflineHeatmap: View {
    let heatmap: RouteHeatmap
    let bounds: CGRect
    let inspection: MapInspection
    let centerRequest: Int
    @State private var zoom = 1.0
    @State private var pan = CGSize.zero
    @State private var frame: PaintedFrame?
    @GestureState private var drag = CGSize.zero

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    HubEyebrow("Offline map", color: HubTheme.boardMuted)
                    Label("North · Drag to pan", systemImage: "arrow.up").font(.caption2)
                }
                .foregroundStyle(HubTheme.boardMuted)
                Spacer()
                Button { changeZoom(1 / 1.5) } label: { Image(systemName: "minus") }
                    .accessibilityLabel("Zoom out").disabled(zoom <= 1)
                Button { changeZoom(1.5) } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Zoom in").disabled(zoom >= 36)
                Button("Fit routes") { zoom = 1; pan = .zero }
            }
            .padding(12)
            .environment(\.colorScheme, .dark)
            Rectangle().fill(HubTheme.boardLine).frame(height: 1)
            GeometryReader { geometry in
                let request = Viewport(size: geometry.size, pan: pan, zoom: zoom)
                let viewport = request.mapRect(bounds: bounds)
                ZStack {
                    Canvas { context, size in drawGrid(context, size: size) }
                    if let frame, let image = frame.image {
                        let scale = request.zoom / frame.viewport.zoom
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .frame(width: frame.viewport.size.width, height: frame.viewport.size.height)
                            .scaleEffect(scale)
                            .offset(x: pan.width - frame.viewport.pan.width * scale + drag.width,
                                    y: pan.height - frame.viewport.pan.height * scale + drag.height)
                    }
                    if let point = inspection.pin?.point, let viewport {
                        let wrappedX = point.x + (viewport.midX - point.x).rounded()
                        Circle().strokeBorder(HubTheme.plotPrimary, lineWidth: 2)
                            .background(.black.opacity(0.25), in: Circle())
                            .frame(width: 17, height: 17)
                            .position(x: (wrappedX - viewport.minX) / viewport.width * geometry.size.width + drag.width,
                                      y: (point.y - viewport.minY) / viewport.height * geometry.size.height + drag.height)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
                .contentShape(Rectangle())
                .gesture(DragGesture()
                    .updating($drag) { value, state, _ in state = value.translation }
                    .onEnded { value in
                        pan.width += value.translation.width
                        pan.height += value.translation.height
                    })
                .simultaneousGesture(SpatialTapGesture().onEnded { tap in
                    guard let viewport else { return }
                    let point = worldPoint(tap.location, in: viewport, size: geometry.size)
                    inspection.select(point, radius: MapInspection.hitRadius * viewport.width / geometry.size.width, on: heatmap)
                })
                .onContinuousHover { phase in
                    guard case .active(let location) = phase, let viewport, drag == .zero else {
                        inspection.clearHover()
                        return
                    }
                    let point = worldPoint(location, in: viewport, size: geometry.size)
                    inspection.hover(point, radius: MapInspection.hitRadius * viewport.width / geometry.size.width, on: heatmap)
                }
                .onChange(of: request) { inspection.clearHover() }
                .onChange(of: drag) { inspection.clearHover() }
                .onChange(of: centerRequest) {
                    guard let viewport else { return }
                    inspection.select(CGPoint(x: viewport.midX, y: viewport.midY),
                                      radius: MapInspection.hitRadius * viewport.width / geometry.size.width,
                                      on: heatmap, showEmpty: true)
                }
                .accessibilityLabel("Offline GPS heatmap")
                .task(id: request) {
                    let routes = heatmap
                    let extent = bounds
                    let render = Task.detached(priority: .userInitiated) {
                        request.draw(routes, bounds: extent)
                    }
                    let image = await withTaskCancellationHandler {
                        await render.value
                    } onCancel: {
                        render.cancel()
                    }
                    guard !Task.isCancelled else { return }
                    frame = PaintedFrame(viewport: request, image: image)
                }
            }
        }.background(HubTheme.boardBackground)
    }

    private struct PaintedFrame {
        let viewport: Viewport
        let image: CGImage?
    }

    private struct Viewport: Equatable, Sendable {
        let size: CGSize
        let pan: CGSize
        let zoom: Double

        func mapRect(bounds: CGRect) -> CGRect? {
            let factor = zoom * min((size.width - 52) / max(0.000025, bounds.width),
                                    (size.height - 52) / max(0.000025, bounds.height))
            guard factor.isFinite, factor > 0 else { return nil }
            return CGRect(x: bounds.midX - (size.width / 2 + pan.width) / factor,
                          y: bounds.midY - (size.height / 2 + pan.height) / factor,
                          width: size.width / factor, height: size.height / factor)
        }

        func draw(_ heatmap: RouteHeatmap, bounds: CGRect) -> CGImage? {
            guard let viewport = mapRect(bounds: bounds) else { return nil }
            let scale = min(1.5, 1_200 / max(size.width, size.height))
            return RouteHeatRaster.image(heatmap, viewport: viewport, width: max(1, Int((size.width * scale).rounded())),
                                         height: max(1, Int((size.height * scale).rounded())), radius: 12 * scale)
        }
    }

    private func worldPoint(_ point: CGPoint, in viewport: CGRect, size: CGSize) -> CGPoint {
        CGPoint(x: viewport.minX + point.x / size.width * viewport.width,
                y: viewport.minY + point.y / size.height * viewport.height)
    }

    private func changeZoom(_ multiplier: Double) {
        let updated = min(36, max(1, zoom * multiplier))
        let scale = updated / zoom
        pan = CGSize(width: pan.width * scale, height: pan.height * scale)
        zoom = updated
    }

    private func drawGrid(_ context: GraphicsContext, size: CGSize) {
        let lines = Path { path in
            for x in stride(from: 0.0, through: size.width, by: 44) {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }
            for y in stride(from: 0.0, through: size.height, by: 44) {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
        }
        context.stroke(lines, with: .color(HubTheme.boardLine.opacity(0.35)), lineWidth: 0.6)
    }
}
