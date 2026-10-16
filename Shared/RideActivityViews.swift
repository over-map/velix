import SwiftUI

/// LiveActivity (P2 §08): lock screen and Dynamic Island views. Shared so the app gallery and snapshot tests render
/// exactly what the extension shows. The island is always dark: its views force the dark colour scheme.
struct LiveActivityLockScreen: View {
    let state: RideActivityAttributes.ContentState

    var body: some View {
        Group {
            if let hazard = state.hazard { hazardBody(hazard) } else { routeBody }
        }
        .padding(14)
    }

    private var routeBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                state.maneuver.icon(size: 37)
                    .foregroundStyle(Color.velix.accentInk)
                    .frame(width: 56, height: 56)
                    .background(Color.velix.accent, in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 0) {
                    Text(state.distance).velixType(.ridingNumber)
                    Text(state.street).velixType(VelixType.ridingStreet.sized(18, lineHeight: 22)).lineLimit(1)
                }
                .foregroundStyle(Color.velix.ink)
                Spacer(minLength: 0)
            }
            HStack {
                Text("\(state.arrival) · \(state.minutesLeft) · \(state.distanceLeft)").lineLimit(1)
                Spacer()
                Text("Velix")
            }
            .velixType(VelixType.ridingLabel.sized(15, lineHeight: 19))
            .foregroundStyle(Color.velix.ink2)
            .padding(.top, 8)
            .overlay(alignment: .top) { Rectangle().fill(Color.velix.line).frame(height: 1) }
        }
        .accessibilityElement(children: .combine)
    }

    private func hazardBody(_ h: RideActivityAttributes.Hazard) -> some View {
        HStack(spacing: 12) {
            VelixIconView(h.glyph, size: 34)
                .foregroundStyle(Color.velix.hazard)
                .frame(width: 56, height: 56)
                .background(Color.velix.hazardInk, in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 0) {
                Text(h.title).velixType(VelixType.ridingStreet.sized(20, lineHeight: 23))
                Text(h.advice).velixType(VelixType.ridingLabel.sized(15, lineHeight: 19))
            }
            Spacer(minLength: 0)
            Text(h.distance).velixType(.ridingNumber)
        }
        .foregroundStyle(Color.velix.hazardInk)
        .accessibilityElement(children: .combine)
    }
}

/// Lock-screen background: surface, or hazard while a hazard is close.
extension RideActivityAttributes.ContentState {
    var lockScreenBackground: Color { hazard == nil ? Color.velix.surface : Color.velix.hazard }
}

/// Dynamic Island compact: leading turn arrow (or hazard glyph), trailing distance.
struct LiveActivityCompactLeading: View {
    let state: RideActivityAttributes.ContentState
    var body: some View {
        Group {
            if let h = state.hazard { VelixIconView(h.glyph, size: 22).foregroundStyle(Color.velix.hazard) }
            else { state.maneuver.icon(size: 22).foregroundStyle(Color.velix.accent) }
        }
        .environment(\.colorScheme, .dark)
    }
}

struct LiveActivityCompactTrailing: View {
    let state: RideActivityAttributes.ContentState
    var body: some View {
        Text(state.hazard?.distance ?? state.distance)
            .velixType(VelixType.ridingNumber.sized(17, lineHeight: 20, trackingEm: 0))
            .foregroundStyle(state.hazard == nil ? Color.velix.ink : Color.velix.hazard)
            .environment(\.colorScheme, .dark)
    }
}

struct LiveActivityMinimal: View {
    let state: RideActivityAttributes.ContentState
    var body: some View {
        Group {
            if let h = state.hazard { VelixIconView(h.glyph, size: 20).foregroundStyle(Color.velix.hazard) }
            else { state.maneuver.icon(size: 20).foregroundStyle(Color.velix.accent) }
        }
        .environment(\.colorScheme, .dark)
    }
}

/// Dynamic Island expanded: arrow, distance and street; arrival and remaining underneath.
struct LiveActivityExpanded: View {
    let state: RideActivityAttributes.ContentState
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                state.maneuver.icon(size: 44).foregroundStyle(Color.velix.accent)
                VStack(alignment: .leading, spacing: 0) {
                    Text(state.distance).velixType(.ridingNumber)
                    Text(state.street).velixType(VelixType.ridingStreet.sized(17, lineHeight: 21)).lineLimit(1)
                }
                .foregroundStyle(Color.velix.ink)
                Spacer(minLength: 0)
            }
            HStack {
                Text("Arrive \(state.arrival)")
                Spacer()
                Text("\(state.minutesLeft) · \(state.distanceLeft)")
            }
            .velixType(VelixType.ridingLabel.sized(15, lineHeight: 19))
            .foregroundStyle(Color.velix.ink2)
        }
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .combine)
    }
}

/// Island chrome for previews, the gallery and snapshots (the system draws the real one): abyss capsule.
struct DynamicIslandFrame<Content: View>: View {
    var width: CGFloat = 230
    var height: CGFloat? = 37
    var cornerRadius: CGFloat = 19
    var padding = EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12)
    @ViewBuilder let content: Content
    var body: some View {
        content
            .padding(padding)
            .frame(width: width, height: height)
            .background(Color.velix.canvas, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .environment(\.colorScheme, .dark)
    }
}
