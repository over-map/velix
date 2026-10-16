import CoreLocation
@preconcurrency import FerrostarCoreFFI
import Foundation
import Testing
@testable import Velix

struct RoutingProfileTests {
    @Test(arguments: RideType.allCases)
    func everyRideTypeHasBestAndFastest(_ type: RideType) throws {
        let profile = try RideProfile.load(type)
        #expect(profile.id == type.rawValue)
        #expect(profile.best.costing == "bicycle")
        #expect(profile.fastest.costingOptions["use_roads"] == .number(1))
        #expect(profile.best.costingOptions["cycling_speed"] == profile.fastest.costingOptions["cycling_speed"])
    }

    @Test func excludePolygonsAreSentAsLonLatRings() throws {
        let json = try ValhallaOnDeviceProvider.requestJSON(
            from: UserLocation(clCoordinateLocation2D: .init(latitude: 45.47, longitude: 9.20)),
            waypoints: [Waypoint(coordinate: GeographicCoordinate(lat: 45.48, lng: 9.22), kind: .break)],
            profile: try RideProfile.load(.city).best,
            excludePolygons: [[[9.2, 45.47], [9.21, 45.47], [9.21, 45.48], [9.2, 45.47]]])
        let body = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let rings = try #require(body["exclude_polygons"] as? [[[Double]]])
        #expect(rings.first?.first == [9.2, 45.47])
    }
}

struct ValhallaRequestTests {
    private func request(course: UInt16? = nil) throws -> [String: Any] {
        let profile = try RideProfile.load(.city).best
        let start = UserLocation(
            coordinates: GeographicCoordinate(lat: 45.4746, lng: 9.2050),
            horizontalAccuracy: 5,
            courseOverGround: course.map { CourseOverGround(degrees: $0, accuracy: 10) },
            timestamp: .now,
            speed: nil
        )
        let json = try ValhallaOnDeviceProvider.requestJSON(
            from: start,
            waypoints: [Waypoint(coordinate: GeographicCoordinate(lat: 45.4781, lng: 9.2272), kind: .break)],
            profile: profile
        )
        return try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    }

    @Test func asksForOsrmWithBannerAndVoiceInstructions() throws {
        let body = try request()
        #expect(body["format"] as? String == "osrm")
        #expect(body["banner_instructions"] as? Bool == true)
        #expect(body["voice_instructions"] as? Bool == true)
        #expect(body["language"] as? String == "en-US")
    }

    @Test func nestsProfileOptionsUnderCosting() throws {
        let body = try request()
        #expect(body["costing"] as? String == "bicycle")
        let options = try #require((body["costing_options"] as? [String: Any])?["bicycle"] as? [String: Any])
        #expect(options["bicycle_type"] as? String == "Hybrid")
    }

    @Test func startCarriesHeadingOnlyWhenCourseKnown() throws {
        let withoutCourse = try #require((try request()["locations"] as? [[String: Any]])?.first)
        #expect(withoutCourse["heading"] == nil)
        let withCourse = try #require((try request(course: 90)["locations"] as? [[String: Any]])?.first)
        #expect(withCourse["heading"] as? Double == 90)
    }

    @Test func destinationIsABreak() throws {
        let locations = try #require(try request()["locations"] as? [[String: Any]])
        #expect(locations.count == 2)
        #expect(locations[1]["type"] as? String == "break")
    }
}
