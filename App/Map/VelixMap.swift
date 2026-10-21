import MapLibre
import SwiftUI

/// Camera for ``VelixMap`` (MapLibre zoom, 512 px tiles: the same zooms as P3).
struct MapCamera: Equatable {
    var center: LatLon
    var zoom: Double
    var pitch: Double = 0
    var bearing: Double = 0
    /// Where the centre sits, as a share of the map's height from the top (riding: the rider low on screen, P5).
    var anchor: Double = 0.5
}

/// How ``VelixMap`` moves to a new camera.
enum MapCameraMotion: Equatable {
    /// The default flight (S1, S3).
    case standard
    /// A view change while riding: 450 ms (`viewMode` token); a cut with Reduce Motion.
    case viewMode(reduceMotion: Bool)
    /// Following the rider fix by fix: a linear glide over the fix interval, so the map doesn't jump.
    case track
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
    /// The rider (P3 puck) when there is no route puck.
    var userLocation: LatLon?
    var userHeading: Double?
    /// Space covered by sheets and bars, so the camera centres in what's left.
    var insets = UIEdgeInsets.zero
    /// Fit these points above the sheets (S3 route options); overrides `camera` while set.
    var fit: [LatLon]?
    var motion: MapCameraMotion = .standard
    /// Riding: coarser tiles far from the camera in the pitched 3D view (see ``Coordinator/applyDetail(on:)``).
    var riding = false
    /// The rider moved the map (S1b: the Recenter button appears).
    var onUserPan: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MLNMapView {
        let map = MLNMapView(frame: .zero)
        map.delegate = context.coordinator
        map.logoView.isHidden = true
        map.compassView.isHidden = true
        map.attributionButton.isHidden = !showsAttribution
        context.coordinator.state = self
        context.coordinator.applyDetail(on: map)
        context.coordinator.loadStyle(on: map)
        context.coordinator.applyCamera(on: map, animated: false)
        return map
    }

    func updateUIView(_ map: MLNMapView, context: Context) {
        let c = context.coordinator
        let old = c.state
        c.state = self
        if old?.riding != riding { c.applyDetail(on: map) }
        if old?.style != style || old?.mode != mode { c.loadStyle(on: map) } else { c.applyStyleState(on: map) }
        if old?.camera != camera || old?.insets != insets || old?.fit != fit { c.applyCamera(on: map, animated: old != nil) }
    }

    @MainActor
    final class Coordinator: NSObject, MLNMapViewDelegate {
        var state: VelixMap?
        private var loaded = false

        func loadStyle(on map: MLNMapView) {
            guard let s = state else { return }
            loaded = false
            styleKey = nil
            shapes = [:]
            travelled = nil
            shown = nil
            glide = nil
            do { map.styleURL = try VelixMapStyle.url(s.style, s.mode) } catch { print("VelixMap: \(error)") }
        }

        /// Riding: tiles far from the camera at lower zooms once pitched beyond 30°, and sooner (scale 1.5). MapLibre's
        /// own threshold is above the 50° 3D view, so it loaded and drew full-detail tiles out to the horizon (most of
        /// them under the banner), which dropped frames on the iPhone 11 at the start and after unlocking.
        func applyDetail(on map: MLNMapView) {
            guard state?.riding == true else { return }
            map.tileLodPitchThreshold = 30 * .pi / 180
            map.tileLodScale = 1.5
        }

        func applyCamera(on map: MLNMapView, animated: Bool) {
            // Timed motions (riding) glide or cut; the standard one keeps MapLibre's flight.
            let motion = state?.motion ?? .standard
            let duration = motion == .standard ? nil : animated ? Self.duration(motion) : 0
            if let pts = state?.fit, pts.count > 1 {
                let lats = pts.map(\.lat), lons = pts.map(\.lon)
                let bounds = MLNCoordinateBounds(sw: CLLocationCoordinate2D(latitude: lats.min()!, longitude: lons.min()!),
                                                 ne: CLLocationCoordinate2D(latitude: lats.max()!, longitude: lons.max()!))
                let i = state?.insets ?? .zero
                map.contentInset = .zero
                let padding = UIEdgeInsets(top: i.top + 40, left: i.left + 40, bottom: i.bottom + 40, right: i.right + 40)
                guard let duration else {
                    map.setVisibleCoordinateBounds(bounds, edgePadding: padding, animated: animated, completionHandler: nil)
                    return
                }
                // North up and flat (S4d), at the view-change pace: the fit worked out here, the padding as content insets.
                guard let fit = Self.fitting(pts, in: map.bounds.size, padding: padding) else { return }
                map.contentInset = padding
                let cam = MLNMapCamera(lookingAtCenter: CLLocationCoordinate2D(latitude: fit.center.lat, longitude: fit.center.lon),
                                       altitude: Self.altitude(for: fit, from: map), pitch: 0, heading: 0)
                map.setCamera(cam, withDuration: duration, animationTimingFunction: CAMediaTimingFunction(name: .easeInEaseOut))
                return
            }
            guard let c = state?.camera else { return }
            map.contentInset = Self.insets(state?.insets ?? .zero, anchor: c.anchor, height: map.bounds.height)
            guard let duration else {
                map.setCenter(CLLocationCoordinate2D(latitude: c.center.lat, longitude: c.center.lon), zoomLevel: c.zoom,
                              direction: c.bearing, animated: animated)
                let cam = map.camera
                cam.pitch = c.pitch
                map.setCamera(cam, animated: animated)
                return
            }
            let center = CLLocationCoordinate2D(latitude: c.center.lat, longitude: c.center.lon)
            let cam = MLNMapCamera(lookingAtCenter: center, altitude: Self.altitude(for: c, from: map), pitch: c.pitch, heading: c.bearing)
            let timing = state?.motion == .track ? CAMediaTimingFunction(name: .linear) : CAMediaTimingFunction(name: .easeInEaseOut)
            map.setCamera(cam, withDuration: duration, animationTimingFunction: timing)
        }

        /// Timed motions; nil for MapLibre's default flight.
        static func duration(_ motion: MapCameraMotion) -> TimeInterval? {
            switch motion {
            case .standard: nil
            case let .viewMode(reduceMotion): reduceMotion ? 0 : VelixMotions.viewMode.durationMs / 1000
            case .track: 1
            }
        }

        /// The north-up camera that shows `points` inside `size` less `padding` (Web Mercator, 512 pt world at z0).
        static func fitting(_ points: [LatLon], in size: CGSize, padding: UIEdgeInsets) -> MapCamera? {
            let w = Double(size.width - padding.left - padding.right), h = Double(size.height - padding.top - padding.bottom)
            guard w > 0, h > 0, !points.isEmpty else { return nil }
            func x(_ lon: Double) -> Double { (lon + 180) / 360 }
            func y(_ lat: Double) -> Double { let s = sin(lat * .pi / 180); return 0.5 - log((1 + s) / (1 - s)) / (4 * .pi) }
            let xs = points.map { x($0.lon) }, ys = points.map { y($0.lat) }
            let (x0, x1, y0, y1) = (xs.min()!, xs.max()!, ys.min()!, ys.max()!)
            let span = max((x1 - x0) * 512 / w, (y1 - y0) * 512 / h, 512 / pow(2, 18) / 256)
            let my = (y0 + y1) / 2
            let lat = atan(sinh(.pi * (1 - 2 * my))) * 180 / .pi
            return MapCamera(center: LatLon(lat: lat, lon: (x0 + x1) / 2 * 360 - 180), zoom: min(18, max(0, log2(1 / span))))
        }

        /// Content insets that put the centre at `anchor` of the height (the rest of the insets kept).
        static func insets(_ base: UIEdgeInsets, anchor: Double, height: CGFloat) -> UIEdgeInsets {
            guard anchor != 0.5, height > 0 else { return base }
            var i = base
            let shift = CGFloat(2 * anchor - 1) * height
            if shift > 0 { i.top += shift } else { i.bottom -= shift }
            return i
        }

        /// The eye altitude for a zoom, scaled from the current camera: MapLibre's altitude halves per zoom level and
        /// goes with cos(pitch) and cos(latitude) (MLNAltitudeForZoomLevel).
        static func altitude(for c: MapCamera, from map: MLNMapView) -> CLLocationDistance {
            let now = map.camera
            let rad = { (d: Double) in d * .pi / 180 }
            let zoom = pow(2, map.zoomLevel - c.zoom)
            let pitch = cos(rad(c.pitch)) / max(0.1, cos(rad(now.pitch)))
            let lat = cos(rad(c.center.lat)) / max(0.1, cos(rad(now.centerCoordinate.latitude)))
            return now.altitude * zoom * pitch * lat
        }

        nonisolated func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            MainActor.assumeIsolated {
                loaded = true
                applyStyleState(on: mapView)
            }
        }

        nonisolated func mapView(_ mapView: MLNMapView, regionWillChangeWith reason: MLNCameraChangeReason, animated: Bool) {
            let byGesture = !reason.intersection([.gesturePan, .gesturePinch, .gestureRotate, .gestureZoomIn, .gestureZoomOut,
                                                  .gestureOneFingerZoom, .gestureTilt]).isEmpty
            guard byGesture else { return }
            MainActor.assumeIsolated { state?.onUserPan() }
        }

        nonisolated func mapView(_ mapView: MLNMapView, didFailToLoadImage imageName: String) -> UIImage? {
            MainActor.assumeIsolated { MapImages.image(named: imageName) }
        }

        /// What was last handed to the style, so an update that changes nothing costs nothing: re-setting a source
        /// makes MapLibre re-place every symbol on it, which shows as dropped frames while riding (once a fix).
        private var styleKey: String?
        private var shapes: [String: Data] = [:]

        func applyStyleState(on map: MLNMapView) {
            guard loaded, let s = state, let style = map.style else { return }
            let key = "\(s.bikeLanes)|\(s.transitLines)|\(s.route == nil)"
            if key != styleKey {
                styleKey = key
                let ids = style.layers.map(\.identifier)
                for (id, on) in VelixMapStyle.visibility(bikeLanes: s.bikeLanes, transitLines: s.transitLines, layerIDs: ids) {
                    style.layer(withIdentifier: id)?.isVisible = on
                }
                // P3: train & metro at 60 % while a route is shown.
                for id in ids where id.hasPrefix("overlay-train") || id.hasPrefix("overlay-metro") {
                    (style.layer(withIdentifier: id) as? MLNLineStyleLayer)?.lineOpacity = NSExpression(forConstantValue: s.route == nil ? 1 : 0.6)
                }
            }
            MapImages.avoidedTexts = Dictionary(uniqueKeysWithValues: (s.route?.avoided ?? []).map { ($0.id, $0.reason) })
            let r = s.route
            setShape("velix-route", r?.routeGeoJSON(), in: style)
            setTravelled(r?.travelled, in: map)
            setShape("velix-hazards", r?.hazardsGeoJSON(), in: style)
            var markers = r ?? MapRouteModel(best: [])
            if markers.puck == nil, let user = s.userLocation { markers.puck = user; markers.heading = s.userHeading ?? 0 }
            setShape("velix-markers", markers.markersGeoJSON(), in: style)
        }

        private var travelled: Double?
        /// The share drawn now, and the glide towards the latest one.
        private var shown: Double?
        private var glide: (from: Double, to: Double, start: CFTimeInterval)?
        private var link: CADisplayLink?
        private weak var map: MLNMapView?

        /// Fades the ridden part of Best's near stretch: a step on line-progress, clear before the rider and the layer's
        /// own colour after. A paint change only, so it follows the rider without re-uploading the route. While tracking it glides
        /// to each new fix over the camera's 1 s, so the cut stays under the chevron instead of running ahead of it.
        private func setTravelled(_ share: Double?, in map: MLNMapView) {
            guard share != travelled else { return }
            travelled = share
            self.map = map
            guard let share, let from = shown, state?.motion == .track, share > from, share - from < 0.05 else {
                glide = nil
                drawTravelled(share)
                return
            }
            glide = (from, share, CACurrentMediaTime())
            if link == nil {
                let l = CADisplayLink(target: self, selector: #selector(stepGlide))
                l.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30)
                l.add(to: .main, forMode: .common)
                link = l
            }
        }

        @objc private func stepGlide() {
            guard let g = glide else { link?.invalidate(); link = nil; return }
            let t = min(1, (CACurrentMediaTime() - g.start) / (Self.duration(.track) ?? 1))
            drawTravelled(g.from + (g.to - g.from) * t)
            if t >= 1 { glide = nil }
        }

        private func drawTravelled(_ share: Double?) {
            shown = share
            guard let style = map?.style else { return }
            for id in ["route-best-near-halo", "route-best-near-casing", "route-best-near"] {
                guard let layer = style.layer(withIdentifier: id) as? MLNLineStyleLayer else { continue }
                guard let share, let color = layer.lineColor.constantValue as? UIColor else { layer.lineGradient = nil; continue }
                let at = NSNumber(value: min(max(share, 0.0001), 0.9999))
                layer.lineGradient = NSExpression(format: "mgl_step:from:stops:($lineProgress, %@, %@)", UIColor.clear, [at: color])
            }
        }

        private func setShape(_ id: String, _ data: Data?, in style: MLNStyle) {
            guard let source = style.source(withIdentifier: id) as? MLNShapeSource else { return }
            let empty = Data(#"{"type":"FeatureCollection","features":[]}"#.utf8)
            let data = data ?? empty
            guard shapes[id] != data else { return }
            shapes[id] = data
            source.shape = try? MLNShape(data: data, encoding: String.Encoding.utf8.rawValue)
        }
    }
}
