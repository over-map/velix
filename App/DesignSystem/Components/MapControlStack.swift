import SwiftUI

/// MapControlStack (P2 §08, S4/S5): voice, view and overview, one 60 × 64 pt cell each (riding targets).
struct MapControlStack: View {
    enum Voice: CaseIterable { case all, alerts, mute }
    enum View3D: CaseIterable { case twoD, threeD, north }

    var voice: Voice = .all
    var view: View3D = .twoD
    var onVoice: () -> Void = {}
    var onView: () -> Void = {}
    var onOverview: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            cell(voiceIcon, voiceLabel, a11y: "Voice: \(voiceLabel)", action: onVoice)
            divider
            cell(viewIcon, viewLabel, a11y: "View: \(viewLabel)", action: onView)
            divider
            cell(.route, "Overview", a11y: "Route overview", action: onOverview)
        }
        .frame(width: 60)
        .background(Color.velix.surface, in: Capsule())
        .velixElevation(VelixElevations.e1, in: Capsule())
    }

    private var divider: some View { Rectangle().fill(Color.velix.line).frame(height: 1) }

    private func cell(_ icon: VelixIcon, _ label: String, a11y: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                VelixIconView(icon, size: 24)
                Text(label).velixType(VelixType.ridingLabel.sized(12, lineHeight: 15))
            }
            .foregroundStyle(Color.velix.ink)
            .frame(width: 60, height: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(VelixPressStyle())
        .accessibilityLabel(a11y)
    }

    private var voiceIcon: VelixIcon { switch voice { case .all: .volume2; case .alerts: .volume1; case .mute: .volumeX } }
    private var voiceLabel: String { switch voice { case .all: "All"; case .alerts: "Alerts"; case .mute: "Mute" } }
    private var viewIcon: VelixIcon { switch view { case .twoD: .navigation2; case .threeD: .rotate3d; case .north: .compass } }
    private var viewLabel: String { switch view { case .twoD: "2D"; case .threeD: "3D"; case .north: "North" } }
}

#Preview {
    HStack(alignment: .top) {
        MapControlStack()
        MapControlStack(voice: .alerts, view: .threeD)
        MapControlStack(voice: .mute, view: .north)
    }
    .padding().background(Color.velix.canvas)
}
