import Foundation
import UIKit
import Testing
@testable import Velix

struct MapTests {
    let route = [LatLon(lat: 45.4746, lon: 9.2050), LatLon(lat: 45.4750, lon: 9.2100), LatLon(lat: 45.4760, lon: 9.2150)]

    @Test func routeModelBuildsTubesAndMarkersAlongTheRoute() throws {
        let hz = [RouteHazard(type: .tram, distanceAlong: 200, lengthM: 0, street: nil, detail: "", osm: "n1"),
                  RouteHazard(type: .cobbles, distanceAlong: 400, lengthM: 70, street: nil, detail: "", osm: "w2")]
        let m = MapRouteModel(best: route, hazards: hz, endName: "Politecnico")
        #expect(m.tubes.count == 2)
        #expect(abs(Geo.length(m.tubes[0]) - 28) < 1)       // ±14 m around a point hazard
        #expect(abs(Geo.length(m.tubes[1]) - 70) < 1)       // a line hazard's own length
        #expect(m.hazards.map(\.type) == [.tram, .cobbles])
        #expect(m.start == route.first && m.end == route.last)

        let fc = try #require(JSONSerialization.jsonObject(with: m.routeGeoJSON()) as? [String: Any])
        let roles = (fc["features"] as? [[String: Any]])?.compactMap { ($0["properties"] as? [String: Any])?["role"] as? String }
        #expect(roles == ["best", "tube", "tube"])
        let hzFC = try #require(JSONSerialization.jsonObject(with: m.hazardsGeoJSON()) as? [String: Any])
        let ranks = (hzFC["features"] as? [[String: Any]])?.compactMap { ($0["properties"] as? [String: Any])?["rank"] as? Int }
        #expect(ranks == [1, 6])   // tram before cobbles (marker collision priority)
    }

    @Test func overlayTogglesSwitchTheMatchingLayers() {
        let ids = ["cycle-protected", "cycle-halo", "overlay-cycle-painted", "eurovelo-ribbon", "overlay-metro", "station-metro",
                   "overlay-station-metro", "road-minor"]
        let off = VelixMapStyle.visibility(bikeLanes: false, transitLines: false, layerIDs: ids)
        #expect(off["cycle-protected"] == true && off["overlay-cycle-painted"] == false && off["eurovelo-ribbon"] == false)
        #expect(off["station-metro"] == true && off["overlay-station-metro"] == false && off["road-minor"] == nil)
        let on = VelixMapStyle.visibility(bikeLanes: true, transitLines: true, layerIDs: ids)
        #expect(on["cycle-protected"] == false && on["overlay-cycle-painted"] == true && on["overlay-metro"] == true)
        #expect(on["station-metro"] == false)
    }

    @Test func styleIsRememberedPerRideType() throws {
        let defaults = try #require(UserDefaults(suiteName: "velix-map-tests-\(UUID().uuidString)"))
        let pref = MapStylePreference(defaults: defaults)
        #expect(pref.style(for: .city) == .standard)
        #expect(pref.style(for: .gravel) == .outdoor)
        pref.set(.satellite, for: .city)
        #expect(pref.style(for: .city) == .satellite)
        #expect(pref.style(for: .road) == .standard)
        pref.set(.outdoor, for: .cargo)            // not offered for Cargo: falls back
        #expect(pref.style(for: .cargo) == .standard)
    }

    @Test func bundledStylesResolveThePackSources() throws {
        let base = URL(fileURLWithPath: "/tmp/pack/basemap.pmtiles"), over = URL(fileURLWithPath: "/tmp/pack/overlays.pmtiles")
        for kind in MapStyleKind.allCases {
            for mode in MapMode.allCases {
                let url = try VelixMapStyle.url(kind, mode, basemap: base, overlays: over)
                let json = try String(contentsOf: url, encoding: .utf8)
                #expect(json.contains("pmtiles://file:///tmp/pack/basemap.pmtiles"))
                #expect(json.contains("pmtiles://file:///tmp/pack/overlays.pmtiles"))
                #expect(!json.contains("velix-pack"))
            }
        }
    }

    @MainActor @Test func runtimeImagesExistForEveryNameTheStylesUse() {
        for name in ["trees-day", "hz-stripe-night", "hz-tram-day", "cnt-12-night", "poi-food-day", "poi-bike-night",
                     "metro-M1.red.0,M3.yellow.0-day", "rail-night", "start-day", "end-night", "puck-34", "ev-EV5"] {
            #expect(MapImages.image(named: name) != nil, "\(name)")
        }
        MapImages.avoidedTexts = ["a0": "Cobbles 300 m"]
        #expect(MapImages.image(named: "avoided-a0-day") != nil)
        #expect(MapImages.image(named: "nope-day") == nil)
    }
}

struct OverviewFitTests {
    @MainActor @Test func fitsTheRouteInsideThePadding() throws {
        // 0.01° of longitude at the equator, 300 pt wide: 512 · 2^z · 0.01/360 = 300 → z ≈ 14.4.
        let fit = try #require(VelixMap.Coordinator.fitting([LatLon(lat: 0, lon: 0), LatLon(lat: 0, lon: 0.01)],
                                                           in: CGSize(width: 380, height: 800),
                                                           padding: UIEdgeInsets(top: 250, left: 40, bottom: 120, right: 40)))
        #expect(abs(fit.zoom - log2(300 * 360 / (0.01 * 512))) < 0.01)
        #expect(abs(fit.center.lon - 0.005) < 1e-9 && abs(fit.center.lat) < 1e-9)
    }
}
