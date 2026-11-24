import Foundation
import UIKit
import Testing
@testable import Velix

struct MapTests {
    let route = [LatLon(lat: 45.4746, lon: 9.2050), LatLon(lat: 45.4750, lon: 9.2100), LatLon(lat: 45.4760, lon: 9.2150)]

    @Test func routeModelBuildsTubesAndMarkersAlongTheRoute() throws {
        let hz = [RouteHazard(type: .steps, distanceAlong: 200, lengthM: 0, street: nil, detail: "", osm: "n1"),
                  RouteHazard(type: .cobbles, distanceAlong: 400, lengthM: 70, street: nil, detail: "", osm: "w2")]
        let m = MapRouteModel(best: route, hazards: hz, endName: "Politecnico", types: Set(HazardType.allCases))
        #expect(m.tubes.count == 2)
        #expect(abs(Geo.length(m.tubes[0]) - 28) < 1)       // ±14 m around a point hazard
        #expect(abs(Geo.length(m.tubes[1]) - 70) < 1)       // a line hazard's own length
        #expect(m.hazards.map(\.type) == [.steps, .cobbles])
        #expect(m.start == route.first && m.end == route.last)

        let fc = try #require(JSONSerialization.jsonObject(with: m.routeGeoJSON()) as? [String: Any])
        let roles = (fc["features"] as? [[String: Any]])?.compactMap { ($0["properties"] as? [String: Any])?["role"] as? String }
        #expect(roles == ["best", "tube", "tube"])
        let hzFC = try #require(JSONSerialization.jsonObject(with: m.hazardsGeoJSON()) as? [String: Any])
        let ranks = (hzFC["features"] as? [[String: Any]])?.compactMap { ($0["properties"] as? [String: Any])?["rank"] as? Int }
        #expect(ranks == [3, 6])   // steps before cobbles (marker collision priority)
    }

    @Test func overlayTogglesSwitchTheMatchingLayers() {
        // Bike lanes only through the overlay (30 Oct): the base map has no cycle layers.
        let ids = ["overlay-cycle-painted", "eurovelo-ribbon", "overlay-metro", "station-metro", "overlay-station-metro", "road-minor"]
        let off = VelixMapStyle.visibility(bikeLanes: false, transitLines: false, layerIDs: ids)
        #expect(off["overlay-cycle-painted"] == false && off["eurovelo-ribbon"] == false)
        #expect(off["station-metro"] == true && off["overlay-station-metro"] == false && off["road-minor"] == nil)
        let on = VelixMapStyle.visibility(bikeLanes: true, transitLines: true, layerIDs: ids)
        #expect(on["overlay-cycle-painted"] == true && on["overlay-metro"] == true)
        #expect(on["station-metro"] == false)
    }

    @Test func buildingsExtrudeOnlyWhenTilted() {
        // Flat: flat roofs with the ground outline on their edge; tilted (riding in 3D or two fingers): extruded (22 Nov).
        let ids = ["building-flat", "building-edge", "building-flat-2d", "building-outline", "building-3d", "building-3d-7", "road-minor"]
        let flat = VelixMapStyle.buildingVisibility(tilted: false, layerIDs: ids)
        #expect(flat["building-flat-2d"] == true && flat["building-outline"] == true)
        #expect(flat["building-3d"] == false && flat["building-3d-7"] == false)
        #expect(flat["building-flat"] == nil && flat["building-edge"] == nil && flat["road-minor"] == nil)
        let tilted = VelixMapStyle.buildingVisibility(tilted: true, layerIDs: ids)
        #expect(tilted["building-flat-2d"] == false && tilted["building-outline"] == false)
        #expect(tilted["building-3d"] == true && tilted["building-3d-7"] == true)
        #expect(VelixMapStyle.isTilted(pitch: 0) == false && VelixMapStyle.isTilted(pitch: 0.4) == false)
        #expect(VelixMapStyle.isTilted(pitch: 2) == true && VelixMapStyle.isTilted(pitch: 55) == true)
    }

    @Test func placeNamesFollowThePhonesLanguage() throws {
        func fields(_ language: String?) -> [String] {
            (VelixMapStyle.placeName(language: language).dropFirst()).compactMap { ($0 as? [Any])?.last as? String }
        }
        #expect(fields("it-IT") == ["name:it", "name:latin", "name"])
        #expect(fields("en") == ["name:en", "name:latin", "name"])
        #expect(fields("de-CH") == ["name:de", "name:latin", "name"])
        #expect(fields("ja-JP") == ["name:latin", "name"])        // no Japanese glyphs: Latin letters
        #expect(fields(nil) == ["name:latin", "name"])
        // Every place label in the bundled styles is one the app renames, and none of the street labels.
        let url = try #require(Bundle.main.url(forResource: "standard-day", withExtension: "json", subdirectory: "MapStyle"))
        let style = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let ids = (style["layers"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
        let renamed = ids.filter { id in VelixMapStyle.placeLabelPrefixes.contains(where: id.hasPrefix) }
        #expect(Set(renamed) == ["label-country", "label-country-minor", "label-region", "label-city", "label-city-dot",
                                 "label-city-dot-minor", "label-town", "label-village", "label-water-lake", "label-water-sea"])
    }

    /// Filippo, 7 Nov: one style for the session, kept across ride types; a new launch starts on the type's own.
    @MainActor @Test func satelliteStaysAcrossRideTypesForTheSession() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "velix-style-\(UUID().uuidString)")
        let store = AppStore(url: dir.appending(path: "state.json"))
        let app = AppModel(store: store, history: RideHistory(inMemory: true))
        #expect(app.mapStyle == .standard)
        app.mapStyle = .satellite
        app.state.rideType = .gravel
        #expect(app.mapStyle == .satellite)
        app.mapStyle = .outdoor
        #expect(app.mapStyle == .outdoor)
        app.state.rideType = .city
        #expect(app.mapStyle == .standard)
        app.mapStyle = .satellite
        let next = AppModel(store: store, history: RideHistory(inMemory: true))
        #expect(next.mapStyle == .standard)
    }

    @Test func bundledStylesReadTheirTilesFromThePacks() throws {
        for kind in MapStyleKind.allCases {
            for mode in MapMode.allCases {
                let json = try String(contentsOf: VelixMapStyle.url(kind, mode), encoding: .utf8)
                #expect(json.contains("https://tiles.velix.invalid/basemap/{z}/{x}/{y}"))
                #expect(json.contains("https://tiles.velix.invalid/overlays/{z}/{x}/{y}"))
                #expect(!json.contains("pmtiles://"))
            }
        }
    }

    @Test func buildingsExtrudeInOneSlice() throws {
        // Each fill-extrusion layer draws every building again: one slice, for the GPU (24 Nov, ≈ 4× less in riding 3D).
        for kind in [MapStyleKind.standard, .outdoor] {
            for mode in MapMode.allCases {
                let style = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: VelixMapStyle.url(kind, mode))) as? [String: Any])
                let extruded = (style["layers"] as? [[String: Any]] ?? []).filter { $0["type"] as? String == "fill-extrusion" }
                #expect(extruded.compactMap { $0["id"] as? String } == ["building-3d"], "\(kind) \(mode)")
            }
        }
    }

    @Test func satelliteDrawsNationalAerialPhotosOverEOX() throws {
        let style = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: VelixMapStyle.url(.satellite, .day))) as? [String: Any])
        let ids = (style["layers"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
        let eox = try #require(ids.firstIndex(of: "imagery")), hd = try #require(ids.firstIndex(of: "imagery-hd"))
        #expect(hd == eox + 1)
        let src = try #require((style["sources"] as? [String: Any])?["imagery-hd"] as? [String: Any])
        #expect((src["tiles"] as? [String]) == ["https://tiles.velix.invalid/imagery-hd/{z}/{x}/{y}"])
        #expect(src["minzoom"] as? Int == 13 && src["maxzoom"] as? Int == 18)
        for kind in [MapStyleKind.standard, .outdoor] {
            #expect(!(try String(contentsOf: VelixMapStyle.url(kind, .day), encoding: .utf8)).contains("imagery-hd"))
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
