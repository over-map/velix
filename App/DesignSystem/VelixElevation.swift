import SwiftUI

struct VelixShadow: Sendable { let y: CGFloat; let blur: CGFloat; let opacity: Double }

struct VelixElevationSpec: Sendable {
    let shadow: VelixShadow?
    let border: Color?
}

/// Elevation: shadow in light mode, border (and shadow) in dark mode (velix-tokens.json → elevation).
struct VelixElevation: Sendable {
    let light: VelixElevationSpec?
    let dark: VelixElevationSpec?
}

private struct VelixElevationModifier<S: InsettableShape>: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    let elevation: VelixElevation
    let shape: S

    func body(content: Content) -> some View {
        let spec = scheme == .dark ? elevation.dark : elevation.light
        content
            .overlay {
                if let border = spec?.border { shape.strokeBorder(border, lineWidth: 1) }
            }
            .shadow(color: Color.velix.paletteAbyss.opacity(spec?.shadow?.opacity ?? 0),
                    radius: (spec?.shadow?.blur ?? 0) / 2, y: spec?.shadow?.y ?? 0)
    }
}

extension View {
    func velixElevation(_ elevation: VelixElevation, in shape: some InsettableShape = RoundedRectangle(cornerRadius: CGFloat.velix.radius.card)) -> some View {
        modifier(VelixElevationModifier(elevation: elevation, shape: shape))
    }
}

