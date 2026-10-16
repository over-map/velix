import SwiftUI

/// NoticeBanner (P2 §08, S1/S3/S5): severe weather, lit streets, late, missed; dismissed weather → compact pill.
struct NoticeBanner: View {
    enum Tone { case warning, info }

    let title: String
    let message: String
    var icon: VelixIconView
    var tone: Tone = .warning
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: CGFloat.velix.s) {
            icon.frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).velixType(.rowTitle)
                Text(message).velixType(.rowSubtitle).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let onDismiss {
                Button(action: onDismiss) { VelixIconView(.x, size: 20).frame(width: 44, height: 44) }
                    .buttonStyle(.plain)
                    .padding(-12)
                    .accessibilityLabel("Dismiss")
            }
        }
        .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 12))
        .foregroundStyle(tone == .warning ? Color.velix.warningInk : Color.velix.ink)
        .background(tone == .warning ? Color.velix.warningSurface : Color.velix.surface,
                    in: RoundedRectangle(cornerRadius: CGFloat.velix.radius.card))
        .velixElevation(tone == .info ? VelixElevations.e1 : VelixElevations.e0)
        .accessibilityElement(children: .combine)
    }
}

/// The dismissed severe-weather notice: a pill that stays on the map ("Storm until 18:00").
struct NoticePill: View {
    let text: String
    var icon: VelixIcon = .cloudLightning
    var body: some View {
        HStack(spacing: 6) {
            VelixIconView(icon, size: 18)
            Text(text).velixType(VelixType.label.sized(14, lineHeight: 18))
        }
        .padding(.horizontal, CGFloat.velix.s)
        .frame(height: 36)
        .foregroundStyle(Color.velix.warningInk)
        .background(Color.velix.warningSurface, in: Capsule())
    }
}

extension NoticeBanner {
    static func weather(_ title: String, _ message: String, onDismiss: @escaping () -> Void = {}) -> NoticeBanner {
        NoticeBanner(title: title, message: message, icon: VelixIconView(.cloudLightning, size: 22), onDismiss: onDismiss)
    }
    static func litStreets(onDismiss: @escaping () -> Void = {}) -> NoticeBanner {
        NoticeBanner(title: "Lit streets only", message: "On for this ride. Switches off when the ride ends.",
                     icon: VelixIconView(.lamp, size: 22), tone: .info, onDismiss: onDismiss)
    }
    static func late(_ title: String, _ message: String) -> NoticeBanner {
        NoticeBanner(title: title, message: message, icon: VelixIconView(.clock, size: 22))
    }
    static func missed(_ title: String, _ message: String) -> NoticeBanner {
        NoticeBanner(title: title, message: message, icon: VelixIconView(.train, size: 22))
    }
}

#Preview {
    VStack(spacing: 16) {
        NoticeBanner.weather("Storm warning until 18:00", "Strong wind and hail in Milan. Consider the train.")
        NoticeBanner.litStreets()
        NoticeBanner.late("Running late, switched to fastest", "You still make the 08:12. Adds 2 rail crossings.")
        NoticeBanner.missed("Missed the 08:12, now on the 08:27", "Arrival 09:41, 15 min later.")
        NoticePill(text: "Storm until 18:00")
    }
    .padding().background(Color.velix.canvas)
}
