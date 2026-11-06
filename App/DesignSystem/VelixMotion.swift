import SwiftUI

/// A motion token (velix-tokens.json → motion). `animation(reduceMotion:)` applies the Reduce Motion fallback.
struct VelixMotion: Sendable {
    let durationMs: Double
    let curve: String

    var animation: Animation {
        let d = durationMs / 1000
        if curve.hasPrefix("spring") { return .spring(response: 0.35, dampingFraction: 0.86) }
        switch curve {
        case "easeInOut": return .easeInOut(duration: d)
        case "linear": return .linear(duration: d)
        default: return .easeOut(duration: d)
        }
    }

    /// Reduce Motion: a short crossfade instead of movement (tokens list each fallback; all are fades or cuts).
    func animation(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : animation
    }
}

/// Press feedback from the `press` token: scale 0.96 (opacity only with Reduce Motion).
struct VelixPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    init() {}
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .opacity(configuration.isPressed && reduceMotion ? 0.7 : 1)
            .animation(VelixMotions.press.animation(reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}

extension Animation {
    /// `animation`, or the Reduce Motion crossfade (0.15 s) when Reduce Motion is on.
    static func velix(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : animation
    }
}

extension AnyTransition {
    /// Sheets and cards slide up from the bottom; with Reduce Motion they fade (P8, motion tokens).
    static func velixRise(reduceMotion: Bool) -> AnyTransition { reduceMotion ? .opacity : .move(edge: .bottom) }
}
