import SwiftUI

/// StartButton / PrimaryButton (P2 §08): 56 pt, radius 16, Familjen Grotesk 700 18.
struct PrimaryButton: View {
    enum Kind { case primary, secondary, danger, ink }

    let title: String
    var icon: VelixIcon?
    var kind: Kind = .primary
    var isEnabled = true
    /// Shown under a disabled button, e.g. "Milan map downloading · 64%. First route after download."
    var disabledNote: String?
    var fullWidth = true
    /// 2 pt casing around the accent button (P4 Start, P7 onboarding).
    var casing = false
    var action: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: action) {
                HStack(spacing: CGFloat.velix.xs) {
                    if let icon { VelixIconView(icon, size: 20) }
                    Text(title).velixType(.button)
                }
                .padding(.horizontal, 20)
                .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: kind == .danger ? CGFloat.velix.touch.riding : 56)
                .foregroundStyle(foreground)
                .background(background, in: RoundedRectangle(cornerRadius: CGFloat.velix.radius.card))
                .overlay {
                    if casing, isEnabled { RoundedRectangle(cornerRadius: CGFloat.velix.radius.card).strokeBorder(Color.velix.casing, lineWidth: 2) }
                }
            }
            .buttonStyle(VelixPressStyle())
            .disabled(!isEnabled)
            if !isEnabled, let disabledNote {
                Text(disabledNote).velixType(.footnote).foregroundStyle(Color.velix.ink2)
            }
        }
    }

    private var foreground: Color {
        guard isEnabled else { return Color.velix.ink3 }
        switch kind {
        case .primary: return Color.velix.accentInk
        case .secondary: return Color.velix.ink
        case .danger: return Color.velix.dangerInk
        case .ink: return Color.velix.surface
        }
    }

    private var background: Color {
        guard isEnabled else { return Color.velix.surface2 }
        switch kind {
        case .primary: return Color.velix.accent
        case .secondary: return Color.velix.surface2
        case .danger: return Color.velix.danger
        case .ink: return Color.velix.ink
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        PrimaryButton(title: "Start", icon: .navigation)
        PrimaryButton(title: "Start", icon: .navigation, isEnabled: false,
                      disabledNote: "Milan map downloading · 64%. First route after download.")
        HStack {
            PrimaryButton(title: "Share GPX", icon: .share, kind: .secondary, fullWidth: false)
            PrimaryButton(title: "End", kind: .danger, fullWidth: false)
        }
    }
    .padding().background(Color.velix.canvas)
}
