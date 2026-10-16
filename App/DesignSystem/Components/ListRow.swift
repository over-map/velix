import SwiftUI

/// The list row P2's You / Routes / summary components share: optional leading tile or icon, title, subtitle,
/// trailing accessory; ≥ 56 pt, hairline above every row but the first.
struct ListRow<Trailing: View>: View {
    enum Leading { case none, icon(VelixIcon), tile(VelixIcon), glyphTile(VelixGlyph) }
    var leading: Leading = .none
    let title: String
    var subtitle: String?
    var subtitleStyle: Color = Color.velix.ink2
    var subtitleBold = false
    var divider = true
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: CGFloat.velix.s) {
            switch leading {
            case .none: EmptyView()
            case let .icon(i): VelixIconView(i, size: 22).foregroundStyle(Color.velix.ink)
            case let .tile(i): tile { VelixIconView(i, size: 22) }
            case let .glyphTile(g): tile { VelixIconView(g, size: 24) }
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(title).velixType(.rowTitle).foregroundStyle(Color.velix.ink)
                if let subtitle {
                    Text(subtitle).velixType(subtitleBold ? VelixType.bodyBold.sized(14, lineHeight: 19) : .rowSubtitle)
                        .foregroundStyle(subtitleStyle)
                }
            }
            Spacer(minLength: 0)
            trailing
        }
        .padding(.vertical, CGFloat.velix.xs)
        .frame(minHeight: 56)
        .overlay(alignment: .top) { if divider { Rectangle().fill(Color.velix.line).frame(height: 1) } }
    }

    private func tile(@ViewBuilder _ content: () -> some View) -> some View {
        content().foregroundStyle(Color.velix.ink)
            .frame(width: 40, height: 40)
            .background(Color.velix.surface2, in: RoundedRectangle(cornerRadius: 10))
    }
}

extension ListRow where Trailing == EmptyView {
    init(leading: Leading = .none, title: String, subtitle: String? = nil, divider: Bool = true) {
        self.init(leading: leading, title: title, subtitle: subtitle, divider: divider) { EmptyView() }
    }
}

/// "✓ Synced" / "✓ On" / "✓ Ready" in success green.
struct StatusCheck: View {
    let text: String
    var body: some View {
        HStack(spacing: 4) {
            VelixIconView(.check, size: 18)
            Text(text).velixType(.label)
        }
        .foregroundStyle(Color.velix.success)
    }
}

/// Small row button: "Connect" (outlined), "Update" / "Retry" (filled surface-2). 36 pt tall, 44 pt hit area.
struct RowButton: View {
    let title: String
    var outlined = false
    var action: () -> Void = {}
    var body: some View {
        Button(action: action) {
            Text(title).velixType(.label).foregroundStyle(Color.velix.ink)
                .padding(.horizontal, 14).frame(height: 36)
                .background(outlined ? Color.clear : Color.velix.surface2, in: RoundedRectangle(cornerRadius: 10))
                .overlay { if outlined { RoundedRectangle(cornerRadius: 10).strokeBorder(Color.velix.ink, lineWidth: 1.5) } }
                .frame(minHeight: CGFloat.velix.touch.min)
                .contentShape(Rectangle())
        }
        .buttonStyle(VelixPressStyle())
    }
}

/// Underlined inline link ("Connect in You").
struct InlineLink: View {
    let title: String
    var action: () -> Void = {}
    var body: some View {
        Button(action: action) {
            Text(title).underline().velixType(.label).foregroundStyle(Color.velix.ink)
                .frame(minHeight: CGFloat.velix.touch.min)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isLink)
    }
}
