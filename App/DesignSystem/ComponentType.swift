import SwiftUI

/// Type styles of the HANDOFF components, taken from P2's component specs (design/Velix P2 Design System v2.dc.html).
/// Built from the token families; sizes the type scale doesn't list (e.g. 15 pt bold labels, 18 pt buttons) are
/// P2's own component sizes (docs/DECISIONS.md, M4).
extension VelixType {
    func sized(_ size: CGFloat, lineHeight: CGFloat? = nil, trackingEm: CGFloat? = nil) -> VelixType {
        VelixType(postScriptName: postScriptName, size: size, lineHeight: lineHeight ?? (self.lineHeight / self.size * size).rounded(),
                  trackingEm: trackingEm ?? self.trackingEm, tabularNumbers: tabularNumbers, riding: riding, relativeTo: relativeTo)
    }

    /// Chip, pill and inline-button labels: Atkinson 700 15.
    static let label = VelixType.bodyBold.sized(15, lineHeight: 20)
    /// List row title: Atkinson 700 16/20.
    static let rowTitle = VelixType.bodyBold.sized(16, lineHeight: 20)
    /// List row subtitle: Atkinson 400 14/19.
    static let rowSubtitle = VelixType.body.sized(14, lineHeight: 19)
    /// Section / state labels: Atkinson 700 11, upper case, 0.06 em.
    static let sectionLabel = VelixType.caption.sized(11, lineHeight: 13, trackingEm: 0.06)
    /// Primary / Start buttons: Familjen Grotesk 700 18.
    static let button = VelixType.headline.sized(18, lineHeight: 22)
    /// Card titles: Familjen Grotesk 700 17/20.
    static let cardTitle = VelixType.headline.sized(17, lineHeight: 20)
    /// Tab bar labels: Atkinson 700 11.
    static let tabLabel = VelixType.caption.sized(11, lineHeight: 13, trackingEm: 0)
    /// Secondary lines (difference line in cards, notes): Atkinson 400 14.
    static let detail = VelixType.body.sized(14, lineHeight: 19)
}

/// Upper-case section label ("ON YOUR ROUTE", "OVERLAYS").
struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .velixType(.sectionLabel)
            .foregroundStyle(Color.velix.ink3)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Icon at a given point size, template-tinted by the foreground style.
struct VelixIconView: View {
    let image: Image
    var size: CGFloat = 24
    init(_ icon: VelixIcon, size: CGFloat = 24) { image = Image(velix: icon); self.size = size }
    init(_ glyph: VelixGlyph, size: CGFloat = 24) { image = Image(velix: glyph); self.size = size }
    var body: some View {
        image.resizable().renderingMode(.template).scaledToFit().frame(width: size, height: size).accessibilityHidden(true)
    }
}


/// iOS-style switch drawn with Velix tokens: on = ink track (never accent, HANDOFF), off = surface2.
struct VelixToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: CGFloat.velix.s) {
                configuration.label
                Spacer(minLength: 0)
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule().fill(configuration.isOn ? Color.velix.ink : Color.velix.surface2)
                        .overlay(Capsule().strokeBorder(Color.velix.line, lineWidth: 1))
                    Circle().fill(configuration.isOn ? Color.velix.surface : Color.velix.toggleThumb)
                        .frame(width: 27, height: 27)
                        .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
                        .padding(2)
                }
                .frame(width: 51, height: 31)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
    }
}
