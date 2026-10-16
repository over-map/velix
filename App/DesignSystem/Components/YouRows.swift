import SwiftUI

/// RuleToggleRow (P2 §08, S6/You): a ride-type rule with its switch; lit streets carries an icon and a note.
struct RuleToggleRow: View {
    let title: String
    var subtitle: String?
    var icon: VelixIcon?
    @Binding var isOn: Bool
    var divider = true

    var body: some View {
        Toggle(isOn: $isOn) {
            ListRow(leading: icon.map { .icon($0) } ?? .none, title: title, subtitle: subtitle, divider: false)
        }
        .toggleStyle(VelixToggleStyle())
        .overlay(alignment: .top) { if divider { Rectangle().fill(Color.velix.line).frame(height: 1) } }
        .accessibilityLabel(title)
    }
}

/// RideRow (P2 §08, Routes · history): one past ride.
struct RideRow: View {
    let destination: String
    let detail: String
    var transit = false
    var divider = true
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            ListRow(leading: transit ? .glyphTile(.train) : .glyphTile(.rideTypeCity), title: destination, subtitle: detail, divider: divider) {
                VelixIconView(.chevronRight, size: 20).foregroundStyle(Color.velix.ink)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

/// ConnectionRow (P2 §08, You): Strava / Apple Health, connected or not.
struct ConnectionRow: View {
    let icon: VelixIcon
    let name: String
    var detail: String?
    var connected: Bool
    var divider = true
    var onConnect: () -> Void = {}

    var body: some View {
        ListRow(leading: .tile(icon), title: name, subtitle: detail, divider: divider) {
            if connected { StatusCheck(text: "On") } else { RowButton(title: "Connect", outlined: true, action: onConnect) }
        }
        .accessibilityElement(children: .combine)
    }
}

/// OfflineRegionRow (P2 §08, You · offline maps): downloading, ready, update available, failed.
struct OfflineRegionRow: View {
    enum State: Equatable {
        case downloading(received: String, total: String, fraction: Double)
        case ready(size: String, updated: String)
        case update(size: String)
        case failed
    }
    let region: String
    let state: State
    var divider = true
    var onAction: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch state {
            case let .downloading(received, total, fraction):
                row("\(received) of \(total) · \(Int((fraction * 100).rounded()))%") {
                    Button(action: onAction) { VelixIconView(.pause, size: 20).foregroundStyle(Color.velix.ink).frame(width: 44, height: 44) }
                        .buttonStyle(.plain).accessibilityLabel("Pause download")
                }
                ProgressBar(fraction: fraction).padding(.leading, 52).padding(.bottom, CGFloat.velix.xs)
            case let .ready(size, updated):
                row("\(size) · updated \(updated)") { StatusCheck(text: "Ready") }
            case let .update(size):
                row("Update · \(size)") { RowButton(title: "Update", action: onAction) }
            case .failed:
                ListRow(leading: .tile(.map), title: region, subtitle: "Download stopped. Check your connection.",
                        subtitleStyle: Color.velix.danger, subtitleBold: true, divider: divider) {
                    RowButton(title: "Retry", action: onAction)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func row(_ subtitle: String, @ViewBuilder trailing: () -> some View) -> some View {
        ListRow(leading: .tile(.map), title: region, subtitle: subtitle, divider: divider, trailing: trailing)
    }
}

/// Thin determinate progress (offline download, onboarding).
struct ProgressBar: View {
    let fraction: Double
    var body: some View {
        GeometryReader { geo in
            Capsule().fill(Color.velix.surface2)
                .overlay(alignment: .leading) { Capsule().fill(Color.velix.ink).frame(width: geo.size.width * max(0, min(1, fraction))) }
        }
        .frame(height: 6)
        .accessibilityValue("\(Int((fraction * 100).rounded())) percent")
    }
}

/// FilterChips (P2 §08, Routes): "Fits City" (current ride type) first, then All / Paved / Gravel / MTB.
struct FilterChips: View {
    let options: [String]
    var leadingGlyph: VelixGlyph?
    @Binding var selected: Int

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: CGFloat.velix.xs) {
                ForEach(Array(options.enumerated()), id: \.offset) { i, option in
                    let on = i == selected
                    Button { selected = i } label: {
                        HStack(spacing: 6) {
                            if i == 0, let leadingGlyph { VelixIconView(leadingGlyph, size: 18) }
                            Text(option).velixType(.label)
                        }
                        .foregroundStyle(on ? Color.velix.surface : Color.velix.ink)
                        .padding(.horizontal, 14).frame(height: 36)
                        .background(on ? Color.velix.ink : Color.velix.surface, in: Capsule())
                        .overlay { if !on { Capsule().strokeBorder(Color.velix.line, lineWidth: 1) } }
                        .frame(minHeight: CGFloat.velix.touch.min)
                    }
                    .buttonStyle(VelixPressStyle())
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
    }
}

/// RouteListCard (P2 §08, Routes): a curated route with its tags and comfort mix; selected adds "Ride this route".
struct RouteListCard: View {
    struct Model: Hashable {
        var tags: [String]
        var name: String
        var detail: String
        var mix: [MixCategory: Double]
    }
    let model: Model
    var selected = false
    var onRide: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: CGFloat.velix.xs) {
            HStack(spacing: 6) {
                ForEach(model.tags, id: \.self) { tag in
                    Text(tag).velixType(VelixType.bodyBold.sized(12, lineHeight: 22, trackingEm: 0.04))
                        .foregroundStyle(Color.velix.ink)
                        .padding(.horizontal, 7)
                        .background(Color.velix.surface2, in: RoundedRectangle(cornerRadius: 6))
                }
            }
            Text(model.name).velixType(.cardTitle).foregroundStyle(Color.velix.ink)
            Text(model.detail).velixType(.detail).foregroundStyle(Color.velix.ink2)
            ComfortMixBar(mix: model.mix, size: .compact)
            if selected { PrimaryButton(title: "Ride this route", icon: .navigation, action: onRide).padding(.top, 4) }
        }
        .padding(.horizontal, 14).padding(.vertical, CGFloat.velix.s)
        .background(Color.velix.surface, in: RoundedRectangle(cornerRadius: CGFloat.velix.radius.card))
        .overlay(RoundedRectangle(cornerRadius: CGFloat.velix.radius.card)
            .strokeBorder(selected ? Color.velix.ink : Color.velix.line, lineWidth: selected ? 2 : 1))
        .velixElevation(selected ? VelixElevations.e2 : VelixElevations.e0)
        .accessibilityElement(children: .contain)
    }
}

extension RouteListCard.Model {
    static let sample = RouteListCard.Model(tags: ["EV5", "Regional"], name: "Naviglio Grande to Abbiategrasso",
                                            detail: "32 km · flat · 4.1 km from you", mix: [.protected: 70, .quiet: 20, .unpaved: 10])
}
