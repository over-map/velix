import CoreLocation
@preconcurrency import FerrostarCoreFFI
import Foundation
import Testing
@testable import Velix

struct RoutingProfileTests {
    @Test func cityProfileLoadsFromAppBundle() throws {
        let profile = try RoutingProfile.load("city")
        #expect(profile.id == "city")
        #expect(profile.costing == "bicycle")
        #expect(profile.costingOptions["bicycle_type"] == .string("hybrid"))
    }

    @Test func missingProfileThrows() {
        #expect(throws: RoutingError.profileMissing("nope")) { try RoutingProfile.load("nope") }
    }
}

struct ValhallaRequestTests {
    private func request(course: UInt16? = nil) throws -> [String: Any] {
        let profile = try RoutingProfile.load("city")
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
        #expect(options["bicycle_type"] as? String == "hybrid")
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
