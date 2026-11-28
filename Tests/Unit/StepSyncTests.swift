import Foundation
import Testing
@testable import Velix

/// Ferrostar's step stuck after a reroute (Filippo, 28 Nov 2026: Pavia ride, turn and ETA frozen 11:22–11:35 while the
/// chevron moved on).
struct StepSyncTests {
    private final class Token {}

    private struct Fixture: Decodable {
        let shape: [[Double]]
        let steps: [[Int]]
        let fixes: [[Double]]
    }

    private func pavia() throws -> (shape: [LatLon], steps: [[LatLon]], fixes: [(LatLon, Double)]) {
        let url = try #require(Bundle(for: Token.self).url(forResource: "ride-step-freeze-pavia", withExtension: "json"))
        let f = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
        let shape = f.shape.map { LatLon(lat: $0[0], lon: $0[1]) }
        return (shape, f.steps.map { Array(shape[$0[0] ... $0[1]]) }, f.fixes.map { (LatLon(lat: $0[0], lon: $0[1]), $0[2]) })
    }

    /// Without the sync the rider never comes within 20 m of the first step's end (Ferrostar's entry check), so the
    /// first step stays current; with it, the step follows the rider.
    @Test func theStepFollowsARiderWhoJoinsTheRouteOnALaterStep() throws {
        let (shape, steps, fixes) = try pavia()
        let ends = StepSync.ends(of: steps)
        let firstEnd = shape[steps[0].count - 1]
        #expect(fixes.allSatisfy { Geo.distance($0.0, firstEnd) > 20 })   // why Ferrostar never advanced

        var track = RouteTrack(shape: shape)
        var current = 0
        for (fix, _) in fixes {
            track.update(fix)
            while StepSync.shouldAdvance(position: track.position, offset: track.offset, ends: ends, current: current) {
                current += 1
            }
        }
        // Five minutes later the rider is on the 3.3 km step (the fourth), and the current step is that one.
        let riding = try #require(ends.firstIndex { $0 >= track.position })
        #expect(riding == 3)
        #expect(current == riding)
    }

    @Test func itNeverRunsAheadOfTheRider() {
        let ends = [100.0, 300.0, 900.0]
        // Not yet clearly past the end of the current step.
        #expect(!StepSync.shouldAdvance(position: 100 + StepSync.margin, offset: 3, ends: ends, current: 0))
        #expect(StepSync.shouldAdvance(position: 100 + StepSync.margin + 1, offset: 3, ends: ends, current: 0))
        // Away from the line: the position along the route is stale.
        #expect(!StepSync.shouldAdvance(position: 500, offset: RouteTrack.snapWithin + 1, ends: ends, current: 0))
        // The last step is left to Ferrostar's arrival.
        #expect(!StepSync.shouldAdvance(position: 2000, offset: 3, ends: ends, current: 2))
        #expect(!StepSync.shouldAdvance(position: 2000, offset: 3, ends: ends, current: 5))
    }

    @Test func stepEndsAddUpAlongTheRoute() {
        let a = LatLon(lat: 45.47, lon: 9.20), b = LatLon(lat: 45.47, lon: 9.2128), c = LatLon(lat: 45.479, lon: 9.2128)
        let ends = StepSync.ends(of: [[a, b], [b, c], [c]])
        #expect(ends.count == 3)
        #expect(abs(ends[0] - 1000) < 15)
        #expect(abs(ends[1] - 2000) < 20)
        #expect(ends[2] == ends[1])
    }
}
