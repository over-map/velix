import SwiftUI

/// MapControlStack (P2 §08, S4/S5): voice, view and overview, one 60 × 64 pt cell each (riding targets). Icons only
/// (Filippo, 7 Nov: "Overview" didn't fit; the icons say it); VoiceOver keeps the names.
struct MapControlStack: View {
    enum Voice: CaseIterable { case all, alerts, mute }
    enum View3D: CaseIterable { case twoD, threeD, north }

    var voice: Voice = .all
    var view: View3D = .twoD
    /// Overview showing (S4d): the cell fills ink.
    var overview = false
    var onVoice: () -> Void = {}
    var onView: () -> Void = {}
    var onOverview: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            cell(voiceIcon, a11y: "Voice: \(voiceA11y)", hint: "Double-tap cycles: \(voiceHint).", action: onVoice)
            divider
            cell(viewIcon, a11y: "View: \(viewA11y)", hint: "Double-tap cycles: \(viewHint).", action: onView)
            divider
            cell(.route, a11y: "Route overview", on: overview, toggle: true, action: onOverview)
        }
        .frame(width: 60)
        .background(Color.velix.surface)
        .clipShape(Capsule())
        .velixElevation(VelixElevations.e1, in: Capsule())
    }

    private var divider: some View { Rectangle().fill(Color.velix.line).frame(height: 1) }

    private func cell(_ icon: VelixIcon, a11y: String, hint: String? = nil, on: Bool = false,
                      toggle: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VelixIconView(icon, size: 26)
                .foregroundStyle(on ? Color.velix.surface : Color.velix.ink)
                .frame(width: 60, height: 64)
                .background(on ? Color.velix.ink : Color.clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(VelixPressStyle())
        .accessibilityLabel(a11y)
        .accessibilityHint(hint ?? "")
        // P8: Overview is a toggle (on / off); the cycling cells are plain buttons.
        .accessibilityAddTraits(toggle ? .isToggle : [])
        .accessibilityValue(toggle ? (on ? "On" : "Off") : "")
    }

    private var voiceIcon: VelixIcon { switch voice { case .all: .volume2; case .alerts: .volume1; case .mute: .volumeX } }
    // P8 S4: "Voice: all prompts", "View: 2D follow", with what the next taps give.
    private var voiceA11y: String { switch voice { case .all: "all prompts"; case .alerts: "alerts only"; case .mute: "mute" } }
    private var voiceHint: String { switch voice { case .all: "alerts only, mute"; case .alerts: "mute, all prompts"; case .mute: "all prompts, alerts only" } }
    private var viewA11y: String { switch view { case .twoD: "2D follow"; case .threeD: "3D follow"; case .north: "north up" } }
    private var viewHint: String { switch view { case .twoD: "3D, north up"; case .threeD: "north up, 2D"; case .north: "2D, 3D" } }
    private var viewIcon: VelixIcon { switch view { case .twoD: .navigation2; case .threeD: .rotate3d; case .north: .compass } }
}

#Preview {
    HStack(alignment: .top) {
        MapControlStack()
        MapControlStack(voice: .alerts, view: .threeD)
        MapControlStack(voice: .mute, view: .north)
        MapControlStack(overview: true)
    }
    .padding().background(Color.velix.canvas)
}
