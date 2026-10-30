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
    /// How much of the map's bottom a panel covers, when it isn't `insets.bottom` (riding: the ETA bar): the ⓘ sits
    /// just above it.
    var coveredBottom: CGFloat?
    /// The rider moved the map (S1b: the Recenter button appears).
    var onUserPan: () -> Void = {}
    /// Routes tab: a tap on a listed route's line (its relation id).
    var onTapRoute: ((Int64) -> Void)?
    /// The camera settled after the rider moved the map: its centre (Routes: "Search routes in this area").
    var onRegionChange: ((LatLon) -> Void)?

    /// How much of the screen's bottom a panel covers, from its top to the screen's bottom edge (the map's insets and
    /// ⓘ follow the panel as it grows or folds).
    static func covered(fromTop minY: CGFloat) -> CGFloat {
        max(0, UIScreen.main.bounds.height - minY)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MLNMapView {
        let map = MLNMapView(frame: .zero)
        map.delegate = context.coordinator
        map.logoView.isHidden = true
        map.compassView.isHidden = true
        map.attributionButton.isHidden = !showsAttribution
        context.coordinator.state = self
        #if DEBUG
        Perf.startHeartbeat()
        #endif
        context.coordinator.applyDetail(on: map)
        context.coordinator.loadStyle(on: map)
        context.coordinator.applyCamera(on: map, animated: false)
        if onTapRoute != nil {
            let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
            // After the map's own double-tap zoom fails.
            for g in map.gestureRecognizers ?? [] where (g as? UITapGestureRecognizer)?.numberOfTapsRequired == 2 { tap.require(toFail: g) }
            map.addGestureRecognizer(tap)
        }
        return map
    }

    func updateUIView(_ map: MLNMapView, context: Context) {
        let c = context.coordinator
        #if DEBUG
        let t0 = CACurrentMediaTime()
        defer { Perf.add("update", CACurrentMediaTime() - t0) }
        #endif
        let old = c.state
        c.state = self
        if old?.riding != riding { c.applyDetail(on: map) }
        if old?.style != style || old?.mode != mode { c.loadStyle(on: map) } else { c.applyStyleState(on: map) }
        if old?.camera != camera || old?.insets != insets || old?.fit != fit { c.applyCamera(on: map, animated: old != nil) }
        else if old?.coveredBottom != coveredBottom { c.placeAttribution(on: map) }
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
            position = nil
            shown = nil
            glide = nil
            windows = [:]
            clearUntil = [:]
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

        /// A fit asked for before the view had a size (a screen's first frame): applied again once the style loads.
        private var cameraPending = false

        func applyCamera(on map: MLNMapView, animated: Bool) {
            cameraPending = map.bounds.isEmpty

            // Timed motions (riding) glide or cut; the standard one keeps MapLibre's flight.
            let motion = state?.motion ?? .standard
            let duration = motion == .standard ? nil : animated ? Self.duration(motion) : 0
            if let pts = state?.fit, pts.count > 1 {
                // The whole route inside what the sheets and bars leave free, with a margin all round, north up and
                // flat: worked out here (MapLibre's own bounds fit drifted under the sheet) and centred in the free
                // area via content insets. Every route overview fits this way (S3, the transit card, S4d, S6).
                let i = state?.insets ?? .zero
                let padding = UIEdgeInsets(top: i.top + Self.fitMargin, left: i.left + Self.fitMargin,
                                           bottom: i.bottom + Self.fitMargin, right: i.right + Self.fitMargin)
                guard let fit = Self.fitting(pts, in: map.bounds.size, padding: padding) else { return }
                map.contentInset = padding
                placeAttribution(on: map)
                let cam = MLNMapCamera(lookingAtCenter: CLLocationCoordinate2D(latitude: fit.center.lat, longitude: fit.center.lon),
                                       altitude: Self.altitude(for: fit, from: map), pitch: 0, heading: 0)
                map.setCamera(cam, withDuration: duration ?? (animated ? 0.35 : 0),
                              animationTimingFunction: CAMediaTimingFunction(name: .easeInEaseOut))
                return
            }
            guard let c = state?.camera else { return }
            map.contentInset = Self.insets(state?.insets ?? .zero, anchor: c.anchor, height: map.bounds.height)
            placeAttribution(on: map)
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

        /// Free space kept around a fitted route.
        static let fitMargin: CGFloat = 40

        /// Timed motions; nil for MapLibre's default flight.
        /// The ⓘ in the bottom-right corner of the map left free (above the sheet), whatever extra inset the fit or the
        /// camera anchor adds: MapLibre lays its ornaments out inside the content inset.
        func placeAttribution(on map: MLNMapView) {
            let free = state?.insets ?? .zero
            let bottom = state?.coveredBottom ?? free.bottom
            map.attributionButtonPosition = .bottomRight
            map.attributionButtonMargins = CGPoint(x: Self.attributionMargin - (map.contentInset.right - free.right),
                                                   y: Self.attributionMargin - (map.contentInset.bottom - bottom))
        }

        static let attributionMargin: CGFloat = 8
        /// 3D riding: 85 % opaque buildings.
        static let ridingBuildingOpacity = 0.85

        static func duration(_ motion: MapCameraMotion) -> TimeInterval? {
            switch motion {
            case .standard: nil
            case let .viewMode(reduceMotion): reduceMotion ? 0 : VelixMotions.viewMode.durationMs / 1000
            // One fix interval (a fix a second, faster in debug time-scale): the glide ends as the next fix lands.
            case .track: 1 / AppClock.scale
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
                if cameraPending { applyCamera(on: mapView, animated: false) }
            }
        }

        nonisolated func mapView(_ mapView: MLNMapView, regionWillChangeWith reason: MLNCameraChangeReason, animated: Bool) {
            let byGesture = !reason.intersection([.gesturePan, .gesturePinch, .gestureRotate, .gestureZoomIn, .gestureZoomOut,
                                                  .gestureOneFingerZoom, .gestureTilt]).isEmpty
            guard byGesture else { return }
            MainActor.assumeIsolated { state?.onUserPan(); movedByUser = true }
        }

        private var movedByUser = false

        nonisolated func mapView(_ mapView: MLNMapView, regionDidChangeWith reason: MLNCameraChangeReason, animated: Bool) {
            MainActor.assumeIsolated {
                guard movedByUser else { return }
                movedByUser = false
                let c = mapView.centerCoordinate
                state?.onRegionChange?(LatLon(lat: c.latitude, lon: c.longitude))
            }
        }

        /// The listed route nearest the tap, within a finger's width.
        @objc func tapped(_ g: UITapGestureRecognizer) {
            guard let map = g.view as? MLNMapView, let onTap = state?.onTapRoute else { return }
            let p = g.location(in: map)
            let rect = CGRect(x: p.x - 22, y: p.y - 22, width: 44, height: 44)
            let ids: Set<String> = ["route-list", "route-focus", "route-list-grey"]
            let hit = map.visibleFeatures(in: rect, styleLayerIdentifiers: ids).compactMap { ($0.attribute(forKey: "id") as? NSNumber)?.int64Value }
            if let id = hit.first { onTap(id) }
        }

        #if DEBUG
        nonisolated func mapViewWillStartRenderingFrame(_ mapView: MLNMapView) {
            MainActor.assumeIsolated { Perf.frameStart = CACurrentMediaTime() }
        }

        nonisolated func mapViewDidFinishRenderingFrame(_ mapView: MLNMapView, fullyRendered: Bool) {
            MainActor.assumeIsolated { Perf.add("frame", CACurrentMediaTime() - Perf.frameStart) }
        }
        #endif

        nonisolated func mapView(_ mapView: MLNMapView, didFailToLoadImage imageName: String) -> UIImage? {
            MainActor.assumeIsolated {
                #if DEBUG
                Perf.add("img:" + imageName.prefix(4), 0)
                #endif
                return MapImages.image(named: imageName)
            }
        }

        /// What was last handed to the style, so an update that changes nothing costs nothing: re-setting a source
        /// makes MapLibre re-place every symbol on it, which shows as dropped frames while riding (once a fix).
        private var styleKey: String?
        private var shapes: [String: Data] = [:]

        func applyStyleState(on map: MLNMapView) {
            guard loaded, let s = state, let style = map.style else { return }
            #if DEBUG
            // `-map-lite a,b`: hide layers whose id starts with any of these (performance experiments).
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-map-lite"), i + 1 < args.count {
                let prefixes = args[i + 1].split(separator: ",").map(String.init)
                for l in style.layers where prefixes.contains(where: { l.identifier.hasPrefix($0) }) { l.isVisible = false }
            }
            if args.contains("-map-poi-notext") {
                for id in ["poi", "poi-civic"] { (style.layer(withIdentifier: id) as? MLNSymbolStyleLayer)?.text = nil }
            }
            #endif
            let key = "\(s.bikeLanes)|\(s.transitLines)|\(s.route == nil)|\(s.riding)|\(s.camera.pitch > 0)"
            if key != styleKey {
                styleKey = key
                let ids = style.layers.map(\.identifier)
                for (id, on) in VelixMapStyle.visibility(bikeLanes: s.bikeLanes, transitLines: s.transitLines, layerIDs: ids) {
                    style.layer(withIdentifier: id)?.isVisible = on
                }
                // Riding in 3D: buildings a little see-through, so the street and the route read through them (30 Oct).
                (style.layer(withIdentifier: "building-3d") as? MLNFillExtrusionStyleLayer)?.fillExtrusionOpacity =
                    NSExpression(forConstantValue: s.riding && s.camera.pitch > 0 ? Self.ridingBuildingOpacity : 1)
                // Riding: only the bike POIs, without names (see tools/stylegen: the full POI layers cost 3 fps).
                for id in ["poi", "poi-civic"] { style.layer(withIdentifier: id)?.isVisible = !s.riding }
                style.layer(withIdentifier: "poi-riding")?.isVisible = s.riding
                // P3: train & metro at 60 % while a route is shown.
                for id in ids where id.hasPrefix("overlay-train") || id.hasPrefix("overlay-metro") {
                    (style.layer(withIdentifier: id) as? MLNLineStyleLayer)?.lineOpacity = NSExpression(forConstantValue: s.route == nil ? 1 : 0.6)
                }
            }
            MapImages.avoidedTexts = Dictionary(uniqueKeysWithValues: (s.route?.avoided ?? []).map { ($0.id, $0.reason) })
            let r = s.route
            setShape("velix-route", r?.routeGeoJSON(), in: style)
            setTravelled(r, in: map)
            setShape("velix-hazards", r?.hazardsGeoJSON(), in: style)
            var markers = r ?? MapRouteModel(best: [])
            if markers.puck == nil, let user = s.userLocation { markers.puck = user; markers.heading = s.userHeading ?? 0 }
            setShape("velix-markers", markers.markersGeoJSON(), in: style)
        }

        /// The rider's position along the route, as last handed over and as drawn now (it glides between fixes).
        private var position: Double?
        private var shown: Double?
        private var glide: (from: Double, to: Double, start: CFTimeInterval)?
        /// Per slot (0, 1): the stretch it draws, and until when a new one stays clear (its shape is uploaded with the
        /// route but drawn a few frames later; its fade is a paint change, applied at once).
        private var windows: [Int: (start: Double, length: Double)] = [:]
        private var clearUntil: [Int: CFTimeInterval] = [:]
        private var link: CADisplayLink?
        private weak var map: MLNMapView?

        /// How long a new stretch waits before it shows: the old one, in the other slot, covers the next 200 m meanwhile.
        static let newStretchDelay: CFTimeInterval = 0.5

        /// Fades the ridden part of the near stretches: a step on line-progress, clear before the rider and the layer's
        /// own colour after. A paint change only, so it follows the rider without re-uploading the route. While tracking
        /// the rider's position glides to each new fix over the camera's step, so the cut stays under the rider.
        private func setTravelled(_ route: MapRouteModel?, in map: MLNMapView) {
            self.map = map
            let now = CACurrentMediaTime()
            var changed = false
            for slot in 0 ... 1 {
                let w = route?.nearWindows.first { $0.slot == slot }.map { (start: $0.start, length: $0.length) }
                if w?.start != windows[slot]?.start || w?.length != windows[slot]?.length {
                    // A stretch replacing another stays clear until its shape is on screen; the first one shows at once.
                    if w != nil, windows[slot] != nil || windows[1 - slot] != nil { clearUntil[slot] = now + Self.newStretchDelay }
                    windows[slot] = w
                    changed = true
                }
            }
            let target = route?.position
            guard target != position || changed else { return }
            position = target
            if let target, let from = shown, state?.motion == .track, target > from, target - from < 40 {
                glide = (from, target, now)
            } else {
                glide = nil
                drawTravelled(target)
            }
            if link == nil, glide != nil || !clearUntil.isEmpty {
                let l = CADisplayLink(target: self, selector: #selector(stepGlide))
                l.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30)
                l.add(to: .main, forMode: .common)
                link = l
            }
        }

        @objc private func stepGlide() {
            guard glide != nil || !clearUntil.isEmpty else { link?.invalidate(); link = nil; return }
            if let g = glide {
                let t = min(1, (CACurrentMediaTime() - g.start) / (Self.duration(.track) ?? 1))
                drawTravelled(g.from + (g.to - g.from) * t)
                if t >= 1 { glide = nil }
            } else {
                drawTravelled(shown)
            }
        }

        static let nearLayers = [["route-best-near-halo", "route-best-near-casing", "route-best-near"],
                                 ["route-best-near-b-halo", "route-best-near-b-casing", "route-best-near-b"]]

        private func drawTravelled(_ position: Double?) {
            #if DEBUG
            let t0 = CACurrentMediaTime()
            defer { Perf.add("fade", CACurrentMediaTime() - t0) }
            #endif
            shown = position
            guard let style = map?.style else { return }
            let now = CACurrentMediaTime()
            for (slot, ids) in Self.nearLayers.enumerated() {
                if let until = clearUntil[slot], now >= until { clearUntil[slot] = nil }
                let w = windows[slot]
                let clear = clearUntil[slot] != nil || w == nil
                for id in ids {
                    guard let layer = style.layer(withIdentifier: id) as? MLNLineStyleLayer else { continue }
                    // No stretch in this slot, or a new one not drawn yet: clear (a removed shape lingers a few frames too).
                    guard let w, let position, !clear, let color = layer.lineColor.constantValue as? UIColor else {
                        layer.lineGradient = NSExpression(forConstantValue: UIColor.clear)
                        continue
                    }
                    let share = (position - w.start) / max(1, w.length)
                    let at = NSNumber(value: min(max(share, 0.0001), 0.9999))
                    layer.lineGradient = NSExpression(format: "mgl_step:from:stops:($lineProgress, %@, %@)", UIColor.clear, [at: color])
                }
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

#if DEBUG
/// `-map-perf`: once a second, frames the map drew and main-thread time in updates and fade steps (console).
@MainActor
enum Perf {
    static let on = ProcessInfo.processInfo.arguments.contains("-map-perf")
    private static var counts: [String: (n: Int, t: Double)] = [:]
    private static var since = CACurrentMediaTime()
    static var frameStart = CACurrentMediaTime()
    /// A 60 Hz heartbeat: fewer ticks than 60 a second means the main thread was busy.
    private static var beat: CADisplayLink?
    private final class Beat: NSObject { @objc func tick() { MainActor.assumeIsolated { Perf.add("main", 0) } } }
    private static let beatTarget = Beat()
    static func startHeartbeat() {
        guard on, beat == nil else { return }
        let l = CADisplayLink(target: beatTarget, selector: #selector(Beat.tick))
        l.add(to: .main, forMode: .common)
        beat = l
    }

    static func add(_ key: String, _ t: Double) {
        guard on else { return }
        let c = counts[key] ?? (0, 0)
        counts[key] = (c.n + 1, c.t + t)
        let now = CACurrentMediaTime()
        guard now - since >= 1 else { return }
        print("PERF " + counts.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value.n)× \(Int($0.value.t * 1000)) ms" }.joined(separator: " · "))
        counts = [:]
        since = now
    }
}
#endif
