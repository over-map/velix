import MapLibre
import SwiftUI

/// Camera for ``VelixMap`` (MapLibre zoom, 512 px tiles: the same zooms as P3).
struct MapCamera: Equatable {
    var center: LatLon
    var zoom: Double
    var pitch: Double = 0
    var bearing: Double = 0
}

/// The Velix map: a P3 style from the region pack, the MapStyleSheet overlays and the route stack.
struct VelixMap: UIViewRepresentable {
    var style: MapStyleKind = .standard
    var mode: MapMode = .day
    var bikeLanes = false
    var transitLines = false
    var route: MapRouteModel?
    var camera: MapCamera
    var showsAttribution = true

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MLNMapView {
        let map = MLNMapView(frame: .zero)
        map.delegate = context.coordinator
        map.logoView.isHidden = true
        map.compassView.isHidden = true
        map.attributionButton.isHidden = !showsAttribution
        context.coordinator.state = self
        context.coordinator.loadStyle(on: map)
        context.coordinator.applyCamera(on: map, animated: false)
        return map
    }

    func updateUIView(_ map: MLNMapView, context: Context) {
        let c = context.coordinator
        let old = c.state
        c.state = self
        if old?.style != style || old?.mode != mode { c.loadStyle(on: map) } else { c.applyStyleState(on: map) }
        if old?.camera != camera { c.applyCamera(on: map, animated: true) }
    }

    @MainActor
    final class Coordinator: NSObject, MLNMapViewDelegate {
        var state: VelixMap?
        private var loaded = false

        func loadStyle(on map: MLNMapView) {
            guard let s = state else { return }
            loaded = false
            do { map.styleURL = try VelixMapStyle.url(s.style, s.mode) } catch { print("VelixMap: \(error)") }
        }

        func applyCamera(on map: MLNMapView, animated: Bool) {
            guard let c = state?.camera else { return }
            map.setCenter(CLLocationCoordinate2D(latitude: c.center.lat, longitude: c.center.lon), zoomLevel: c.zoom,
                          direction: c.bearing, animated: animated)
            let cam = map.camera
            cam.pitch = c.pitch
            map.setCamera(cam, animated: animated)
        }

        nonisolated func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            MainActor.assumeIsolated {
                loaded = true
                applyStyleState(on: mapView)
            }
        }

        nonisolated func mapView(_ mapView: MLNMapView, didFailToLoadImage imageName: String) -> UIImage? {
            MainActor.assumeIsolated { MapImages.image(named: imageName) }
        }

        func applyStyleState(on map: MLNMapView) {
            guard loaded, let s = state, let style = map.style else { return }
            let ids = style.layers.map(\.identifier)
            for (id, on) in VelixMapStyle.visibility(bikeLanes: s.bikeLanes, transitLines: s.transitLines, layerIDs: ids) {
                style.layer(withIdentifier: id)?.isVisible = on
            }
            // P3: train & metro at 60 % while a route is shown.
            for id in ids where id.hasPrefix("overlay-train") || id.hasPrefix("overlay-metro") {
                (style.layer(withIdentifier: id) as? MLNLineStyleLayer)?.lineOpacity = NSExpression(forConstantValue: s.route == nil ? 1 : 0.6)
            }
            MapImages.avoidedTexts = Dictionary(uniqueKeysWithValues: (s.route?.avoided ?? []).map { ($0.id, $0.reason) })
            let r = s.route
            setShape("velix-route", r?.routeGeoJSON(), in: style)
            setShape("velix-hazards", r?.hazardsGeoJSON(), in: style)
            setShape("velix-markers", r?.markersGeoJSON(), in: style)
        }

        private func setShape(_ id: String, _ data: Data?, in style: MLNStyle) {
            guard let source = style.source(withIdentifier: id) as? MLNShapeSource else { return }
            let empty = Data(#"{"type":"FeatureCollection","features":[]}"#.utf8)
            source.shape = try? MLNShape(data: data ?? empty, encoding: String.Encoding.utf8.rawValue)
        }
    }
}
