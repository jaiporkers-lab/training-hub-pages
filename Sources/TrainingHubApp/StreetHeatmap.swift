import MapKit
import SwiftUI
import TrainingHubCore

/// Apple Maps loads when the Map workspace displays the street basemap.
struct StreetHeatmap: NSViewRepresentable {
    let heatmap: RouteHeatmap
    let bounds: CGRect
    let inspection: MapInspection
    let pin: CGPoint?
    let centerRequest: Int

    func makeCoordinator() -> Coordinator { Coordinator(heatmap: heatmap, inspection: inspection, centerRequest: centerRequest) }

    func makeNSView(context: Context) -> MKMapView {
        let map = FitMapView()
        let coordinator = context.coordinator
        map.delegate = coordinator
        map.onPointer = { [weak map, weak coordinator] location in
            guard let map, let coordinator else { return }
            coordinator.hover(location, on: map)
        }
        let click = NSClickGestureRecognizer(target: coordinator, action: #selector(Coordinator.click(_:)))
        click.delegate = coordinator
        map.addGestureRecognizer(click)
        map.appearance = NSAppearance(named: .darkAqua)
        map.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
        map.showsUserLocation = false
        map.showsScale = true
        map.isPitchEnabled = false
        map.isRotateEnabled = false
        let world = MKMapRect.world.width
        let size = CGSize(width: max(0.000025, bounds.width), height: max(0.000025, bounds.height))
        map.initialRect = MKMapRect(x: (bounds.midX - size.width / 2) * world, y: (bounds.midY - size.height / 2) * world,
                                   width: size.width * world, height: size.height * world)
        map.addOverlay(HeatOverlay(heatmap: heatmap, bounds: bounds), level: .aboveRoads)
        return map
    }

    func updateNSView(_ nsView: MKMapView, context: Context) {
        context.coordinator.showPin(pin, on: nsView)
        context.coordinator.inspectCenter(centerRequest, on: nsView)
    }

    private final class FitMapView: MKMapView {
        var initialRect: MKMapRect?
        var onPointer: ((CGPoint?) -> Void)?
        private var pointerArea: NSTrackingArea?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let pointerArea { removeTrackingArea(pointerArea) }
            let area = NSTrackingArea(rect: .zero, options: [.inVisibleRect, .activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited],
                                      owner: self, userInfo: nil)
            addTrackingArea(area)
            pointerArea = area
        }

        override func mouseMoved(with event: NSEvent) {
            onPointer?(convert(event.locationInWindow, from: nil))
            super.mouseMoved(with: event)
        }

        override func mouseExited(with event: NSEvent) {
            onPointer?(nil)
            super.mouseExited(with: event)
        }

        override func layout() {
            super.layout()
            guard bounds.width > 70, bounds.height > 70, let rect = initialRect else { return }
            initialRect = nil
            setVisibleMapRect(rect, edgePadding: NSEdgeInsets(top: 35, left: 35, bottom: 35, right: 35), animated: false)
        }
    }

    private final class HeatOverlay: NSObject, MKOverlay {
        let heatmap: RouteHeatmap
        let coordinate: CLLocationCoordinate2D
        let boundingMapRect: MKMapRect

        init(heatmap: RouteHeatmap, bounds: CGRect) {
            self.heatmap = heatmap
            let world = MKMapRect.world.width
            coordinate = MKMapPoint(x: (bounds.midX - floor(bounds.midX)) * world, y: bounds.midY * world).coordinate
            let padded = bounds.insetBy(dx: -0.015, dy: -0.015)
            if padded.minX < 0 || padded.maxX > 1 {
                boundingMapRect = .world
            } else {
                boundingMapRect = MKMapRect(x: padded.minX * world, y: max(0, padded.minY) * world,
                                           width: padded.width * world, height: (min(1, padded.maxY) - max(0, padded.minY)) * world)
            }
        }
    }

    private final class HeatRenderer: MKOverlayRenderer {
        private let heatmap: RouteHeatmap

        init(_ overlay: HeatOverlay) {
            heatmap = overlay.heatmap
            super.init(overlay: overlay)
        }

        override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
            let world = MKMapRect.world.width
            let screenWidth = mapRect.width * zoomScale
            let screenHeight = mapRect.height * zoomScale
            guard screenWidth > 0, screenWidth.isFinite, screenHeight > 0, screenHeight.isFinite else { return }
            let scale = min(1.5, 768 / max(screenWidth, screenHeight))
            let width = max(1, Int((screenWidth * scale).rounded()))
            let height = max(1, Int((screenHeight * scale).rounded()))
            let viewport = CGRect(x: mapRect.minX / world, y: mapRect.minY / world,
                                  width: mapRect.width / world, height: mapRect.height / world)
            guard let heat = RouteHeatRaster.image(heatmap, viewport: viewport, width: width, height: height, radius: 12 * scale) else { return }
            let target = rect(for: mapRect)
            context.saveGState()
            // MapKit's map points increase south, while CGContext draws images bottom-up.
            context.translateBy(x: target.minX, y: target.maxY)
            context.scaleBy(x: 1, y: -1)
            context.draw(heat, in: CGRect(origin: .zero, size: target.size))
            context.restoreGState()
        }
    }

    @MainActor
    final class Coordinator: NSObject, MKMapViewDelegate, NSGestureRecognizerDelegate {
        private let heatmap: RouteHeatmap
        private let inspection: MapInspection
        private var pin: MKPointAnnotation?
        private var pinnedPoint: CGPoint?
        private var centerRequest: Int

        init(heatmap: RouteHeatmap, inspection: MapInspection, centerRequest: Int) {
            self.heatmap = heatmap
            self.inspection = inspection
            self.centerRequest = centerRequest
        }

        func hover(_ location: CGPoint?, on map: MKMapView) {
            guard let location, let hit = hitLocation(location, on: map) else {
                inspection.clearHover()
                return
            }
            inspection.hover(hit.point, radius: hit.radius, on: heatmap)
        }

        @objc func click(_ gesture: NSClickGestureRecognizer) {
            guard let map = gesture.view as? MKMapView, let hit = hitLocation(gesture.location(in: map), on: map) else { return }
            inspection.select(hit.point, radius: hit.radius, on: heatmap)
        }

        func inspectCenter(_ request: Int, on map: MKMapView) {
            guard request != centerRequest else { return }
            centerRequest = request
            let center = CGPoint(x: map.bounds.midX, y: map.bounds.midY)
            guard let hit = hitLocation(center, on: map) else { return }
            Task { inspection.select(hit.point, radius: hit.radius, on: heatmap, showEmpty: true) }
        }

        private func hitLocation(_ location: CGPoint, on map: MKMapView) -> (point: CGPoint, radius: Double)? {
            guard map.bounds.contains(location), map.bounds.width > 0 else { return nil }
            let coordinate = map.convert(location, toCoordinateFrom: map)
            guard CLLocationCoordinate2DIsValid(coordinate) else { return nil }
            let point = MKMapPoint(coordinate)
            let world = MKMapRect.world.width
            return (CGPoint(x: point.x / world, y: point.y / world),
                    MapInspection.hitRadius * map.visibleMapRect.width / map.bounds.width / world)
        }

        func showPin(_ point: CGPoint?, on map: MKMapView) {
            guard point != pinnedPoint else { return }
            pinnedPoint = point
            if let pin { map.removeAnnotation(pin) }
            pin = nil
            if let point {
                let world = MKMapRect.world.width
                let marker = MKPointAnnotation()
                marker.coordinate = MKMapPoint(x: (point.x - floor(point.x)) * world, y: point.y * world).coordinate
                map.addAnnotation(marker)
                pin = marker
            }
        }

        func gestureRecognizer(_ gestureRecognizer: NSGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: NSGestureRecognizer) -> Bool { true }

        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) { inspection.clearHover() }

        func mapView(_ mapView: MKMapView, rendererFor overlay: any MKOverlay) -> MKOverlayRenderer {
            if let heat = overlay as? HeatOverlay { return HeatRenderer(heat) }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}
