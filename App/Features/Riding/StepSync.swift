import Foundation

/// Keeps Ferrostar's current step with the rider. Ferrostar moves to the next step only after a fix within 20 m of
/// the current step's end (`stepAdvanceDistanceEntryAndExit`). A reroute can start on a road beside the rider, whose
/// end the rider never reaches: they join the route on a later step, Ferrostar calls that "off the step, on the route"
/// (no reroute), and the turn and the ETA freeze while the chevron moves on (Filippo, 28 Nov 2026: Pavia, 11:22–11:35).
/// When the rider's position along the route (``RouteTrack``) is clearly past the current step's end, the session
/// advances the step.
enum StepSync {
    /// How far past a step's end the rider must be before the app advances it (Ferrostar's own exit is 5 m).
    static let margin = 20.0

    /// Each step's end, in metres from the start of the route, measured like ``RouteTrack``.
    static func ends(of steps: [[LatLon]]) -> [Double] {
        var total = 0.0
        return steps.map { geometry in
            total += RouteAnalyzer.cumulative(geometry).last ?? 0
            return total
        }
    }

    /// Whether to advance past `current`: the rider is on the line and past its end; never the last step (arrival).
    static func shouldAdvance(position: Double, offset: Double, ends: [Double], current: Int) -> Bool {
        guard current >= 0, current < ends.count - 1, offset <= RouteTrack.snapWithin else { return false }
        return position > ends[current] + margin
    }
}
