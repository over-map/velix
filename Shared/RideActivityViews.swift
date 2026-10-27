import SwiftUI

/// LiveActivity (P5 §04–05: L1–L2, D1–D5): lock screen and Dynamic Island views. Shared so the app gallery and
/// snapshot tests render exactly what the extension shows. The island is always dark: its views force the dark
/// colour scheme.
struct LiveActivityLockScreen: View {
    let state: RideActivityAttributes.ContentState

    var body: some View {
        Group {
            if let train = state.train { trainBody(train) }
            else if let hazard = state.hazard { hazardBody(hazard) } else { routeBody }
        }
        .padding(14)
    }

    /// L3: on the train, the countdown to the stop.
    private func trainBody(_ t: RideActivityAttributes.Train) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Group {
                    if t.metro { VelixIconView(VelixGlyph.metro, size: 34) } else { VelixIconView(VelixIcon.trainFront, size: 34) }
                }
                .foregroundStyle(Color.velix.surface)
                .frame(width: 60, height: 60)
                .background(Color.velix.transitTrain, in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Get off at \(t.station)").velixType(VelixType.ridingStreet.sized(22, lineHeight: 24)).lineLimit(1)
                    Text(t.next).velixType(VelixType.ridingLabel.sized(15, lineHeight: 19)).foregroundStyle(Color.velix.ink2).lineLimit(1)
                }
                Spacer(minLength: 0)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(t.minutes).velixType(VelixType.ridingBigNumber.sized(44, lineHeight: 44))
                    Text("min").velixType(VelixType.ridingStreet.sized(18, lineHeight: 20))
                }
            }
            .foregroundStyle(Color.velix.ink)
            HStack(spacing: 6) {
                VelixIconView(.bike, size: 18)
                Text(t.carriage).lineLimit(1)
                Spacer(minLength: 0)
                Text(t.arrival)
            }
            .velixType(VelixType.ridingLabel.sized(15, lineHeight: 19))
            .foregroundStyle(Color.velix.ink)
            .padding(.top, 10)
            .overlay(alignment: .top) { Rectangle().fill(Color.velix.line).frame(height: 1) }
        }
        .accessibilityElement(children: .combine)
    }

    /// L1: the next maneuver large, then the next hazard and the arrival in one line.
    private var routeBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                state.maneuver.icon(size: 40)
                    .foregroundStyle(Color.velix.accentInk)
                    .frame(width: 60, height: 60)
                    .background(Color.velix.accent, in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 3) {
                    Text(state.distance).velixType(VelixType.ridingBigNumber.sized(40, lineHeight: 40))
                    Text(state.street).velixType(VelixType.ridingStreet.sized(19, lineHeight: 23)).lineLimit(1)
                }
                .foregroundStyle(Color.velix.ink)
                Spacer(minLength: 0)
            }
            HStack(spacing: 10) {
                if let next = state.nextHazard {
                    VelixIconView(next.glyph, size: 18)
                        .foregroundStyle(Color.velix.hazardInk)
                        .frame(width: 28, height: 28)
                        .background(Color.velix.hazard, in: RoundedRectangle(cornerRadius: 7))
                    Text(next.text).foregroundStyle(Color.velix.ink2).lineLimit(1)
                    Spacer(minLength: 0)
                    Text("\(state.arrival) · \(state.minutesLeft)").foregroundStyle(Color.velix.ink).lineLimit(1).fixedSize()
                } else {
                    Text("Arrive \(state.arrival)").foregroundStyle(Color.velix.ink)
                    Spacer(minLength: 0)
                    Text("\(state.minutesLeft) · \(state.distanceLeft)").foregroundStyle(Color.velix.ink2).lineLimit(1)
                }
            }
            .velixType(VelixType.ridingLabel.sized(15, lineHeight: 19))
            .padding(.top, 10)
            .overlay(alignment: .top) { Rectangle().fill(Color.velix.line).frame(height: 1) }
        }
        .accessibilityElement(children: .combine)
        // P8: "Turn left in 160 metres, Via Nino Bixio. Tram rails in 160 metres. Arrive 08:42."
        .accessibilityLabel("\(state.maneuver.spoken) in \(Self.spoken(state.distance)), \(state.street). "
                            + (state.nextHazard.map { "\(Self.spoken($0.text)). " } ?? "") + "Arrive \(state.arrival).")
    }

    /// L2: the hazard leads; the maneuver drops to the footer.
    private func hazardBody(_ h: RideActivityAttributes.Hazard) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                VelixIconView(h.glyph, size: 34)
                    .foregroundStyle(Color.velix.hazard)
                    .frame(width: 60, height: 60)
                    .background(Color.velix.hazardInk, in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 2) {
                    Text(h.title).velixType(VelixType.ridingStreet.sized(22, lineHeight: 24))
                    Text(h.advice).velixType(VelixType.ridingLabel.sized(16, lineHeight: 20)).lineLimit(1)
                }
                Spacer(minLength: 0)
                Text(h.distance).velixType(VelixType.ridingBigNumber.sized(40, lineHeight: 40))
            }
            HStack(spacing: 6) {
                state.maneuver.icon(size: 18)
                Text("\(state.distance) · \(state.street)").lineLimit(1)
                Spacer(minLength: 0)
                Text(state.arrival)
            }
            .velixType(VelixType.ridingLabel.sized(15, lineHeight: 19))
            .padding(.top, 8)
            .overlay(alignment: .top) { Rectangle().fill(Color.velix.hazardInk.opacity(0.25)).frame(height: 1) }
        }
        .foregroundStyle(Color.velix.hazardInk)
        .accessibilityElement(children: .combine)
    }

    static func spoken(_ s: String) -> String {
        s.replacingOccurrences(of: " km", with: " kilometres").replacingOccurrences(of: " m", with: " metres")
    }
}

/// Lock-screen background (P5 L1 / L2): surface at 92 %, or hazard while a hazard is close.
extension RideActivityAttributes.ContentState {
    var lockScreenBackground: Color { hazard == nil ? Color.velix.surface.opacity(0.92) : Color.velix.hazard }
}

/// Dynamic Island compact (D1 / D2): turn arrow (or hazard glyph) leading, distance trailing.
struct LiveActivityCompactLeading: View {
    let state: RideActivityAttributes.ContentState
    var body: some View {
        Group {
            if state.train != nil { VelixIconView(VelixIcon.trainFront, size: 22).foregroundStyle(Color.velix.transitTrain) }
            else if let h = state.hazard { VelixIconView(h.glyph, size: 22).foregroundStyle(Color.velix.hazard) }
            else { state.maneuver.icon(size: 22).foregroundStyle(Color.velix.accent) }
        }
        .environment(\.colorScheme, .dark)
    }
}

struct LiveActivityCompactTrailing: View {
    let state: RideActivityAttributes.ContentState
    var body: some View {
        Text(state.train.map { "\($0.station) \($0.minutes) min" } ?? state.hazard?.distance ?? state.distance)
            .velixType(VelixType.ridingNumber.sized(17, lineHeight: 20, trackingEm: 0))
            .foregroundStyle(state.hazard == nil ? Color.velix.ink : Color.velix.hazard)
            .environment(\.colorScheme, .dark)
    }
}

/// D3 minimal (another app holds the island): always the next arrow.
struct LiveActivityMinimal: View {
    let state: RideActivityAttributes.ContentState
    var body: some View {
        state.maneuver.icon(size: 20).foregroundStyle(Color.velix.accent)
            .environment(\.colorScheme, .dark)
    }
}

/// Dynamic Island expanded (D4 / D5): maneuver, street, next hazard and arrival; the hazard leads when close.
struct LiveActivityExpanded: View {
    let state: RideActivityAttributes.ContentState
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let t = state.train {
                HStack(spacing: 14) {
                    VelixIconView(VelixIcon.trainFront, size: 32)
                        .foregroundStyle(Color.velix.canvas)
                        .frame(width: 56, height: 56)
                        .background(Color.velix.transitTrain, in: RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Get off at \(t.station)").velixType(VelixType.ridingStreet.sized(22, lineHeight: 24)).lineLimit(1)
                        Text(t.next).velixType(VelixType.ridingLabel.sized(15, lineHeight: 19)).foregroundStyle(Color.velix.ink2)
                    }
                    .foregroundStyle(Color.velix.ink)
                    Spacer(minLength: 0)
                    Text("\(t.minutes) min").velixType(VelixType.ridingBigNumber.sized(36, lineHeight: 36)).foregroundStyle(Color.velix.ink)
                }
            } else if let n = state.notice {
                // D7: late or missed leads, in the warning colours; the maneuver drops to the footer.
                HStack(spacing: 14) {
                    VelixIconView(.timer, size: 32)
                        .foregroundStyle(Color.velix.warningInk)
                        .frame(width: 56, height: 56)
                        .background(Color.velix.warningSurface, in: RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(n.title).velixType(VelixType.ridingStreet.sized(22, lineHeight: 24)).foregroundStyle(Color.velix.warningInk)
                        Text(n.message).velixType(VelixType.ridingLabel.sized(15, lineHeight: 19)).foregroundStyle(Color.velix.ink).lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
            } else if let h = state.hazard {
                HStack(spacing: 14) {
                    VelixIconView(h.glyph, size: 32)
                        .foregroundStyle(Color.velix.hazardInk)
                        .frame(width: 56, height: 56)
                        .background(Color.velix.hazard, in: RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(h.title).velixType(VelixType.ridingStreet.sized(22, lineHeight: 24)).foregroundStyle(Color.velix.hazard)
                        Text(h.longAdvice ?? h.advice).velixType(VelixType.ridingLabel.sized(16, lineHeight: 20))
                            .foregroundStyle(Color.velix.ink).lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    Text(h.distance).velixType(VelixType.ridingBigNumber.sized(36, lineHeight: 36)).foregroundStyle(Color.velix.hazard)
                }
            } else {
                HStack(spacing: 14) {
                    state.maneuver.icon(size: 38)
                        .foregroundStyle(Color.velix.accentInk)
                        .frame(width: 56, height: 56)
                        .background(Color.velix.accent, in: RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(state.distance).velixType(VelixType.ridingBigNumber.sized(36, lineHeight: 36))
                        Text(state.street).velixType(VelixType.ridingStreet.sized(18, lineHeight: 22)).lineLimit(1)
                    }
                    .foregroundStyle(Color.velix.ink)
                    Spacer(minLength: 0)
                }
            }
            HStack(spacing: 8) {
                if let t = state.train {
                    VelixIconView(.bike, size: 18)
                    Text(t.carriage).lineLimit(1)
                } else if state.notice != nil || state.hazard != nil {
                    state.maneuver.icon(size: 18)
                    Text("\(state.distance) · \(state.street)").lineLimit(1)
                } else if let next = state.nextHazard {
                    VelixIconView(next.glyph, size: 15)
                        .foregroundStyle(Color.velix.hazardInk)
                        .frame(width: 24, height: 24)
                        .background(Color.velix.hazard, in: RoundedRectangle(cornerRadius: 6))
                    Text(next.text).lineLimit(1)
                } else {
                    Text("Arrive \(state.arrival)")
                }
                Spacer(minLength: 0)
                Text(state.train.map(\.arrival) ?? state.spare ?? (state.nextHazard == nil && state.hazard == nil ? "\(state.minutesLeft) · \(state.distanceLeft)"
                     : "\(state.arrival) · \(state.minutesLeft)")).fixedSize()
            }
            .velixType(VelixType.ridingLabel.sized(15, lineHeight: 19))
            .foregroundStyle(Color.velix.ink2)
        }
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .combine)
    }
}

/// Island chrome for previews, the gallery and snapshots (the system draws the real one): black capsule.
struct DynamicIslandFrame<Content: View>: View {
    var width: CGFloat = 236
    var height: CGFloat? = 37
    var cornerRadius: CGFloat = 19
    var padding = EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 14)
    @ViewBuilder let content: Content
    var body: some View {
        content
            .padding(padding)
            .frame(width: width, height: height)
            .background(Color.black, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .environment(\.colorScheme, .dark)
    }
}
