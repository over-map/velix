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

/// RideRow (P7 S8 · Your rides): one past ride, its ride-type glyph (the train for bike + transit) and distance.
struct RideRow: View {
    let destination: String
    let detail: String
    var glyph: VelixGlyph = .rideTypeCity
    var transit = false
    /// "5.4 km" (P7); without it a chevron.
    var value: String?
    var divider = true
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            ListRow(leading: .glyphTile(transit ? .train : glyph), title: destination, subtitle: detail, divider: divider) {
                if let value {
                    Text(value).velixType(.bodyBold).monospacedDigit().foregroundStyle(Color.velix.ink2).lineLimit(1).fixedSize()
                } else {
                    VelixIconView(.chevronRight, size: 20).foregroundStyle(Color.velix.ink)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

/// OfflineRegionRow (P2 §08, You · offline maps): downloading, ready, update available, failed, on offer. A downloaded
/// region shows Remove when it can go (Filippo, 5 Nov: the long-press wasn't found).
struct OfflineRegionRow: View {
    enum State: Equatable {
        case downloading(received: String, total: String, fraction: Double)
        case ready(size: String, updated: String)
        case update(size: String)
        case failed
        /// On offer, not downloaded (Filippo, 2 Nov: other regions).
        case available(size: String)
    }
    let region: String
    let state: State
    var divider = true
    /// Download, Update or Retry; Cancel while downloading.
    var onAction: () -> Void = {}
    /// Remove a downloaded region (`nil`: it stays, e.g. the last one).
    var onRemove: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch state {
            case let .downloading(received, total, fraction):
                row("\(received) of \(total) · \(Int((fraction * 100).rounded()))%") {
                    RowButton(title: "Cancel", action: onAction).accessibilityLabel("Cancel download")
                }
                ProgressBar(fraction: fraction).padding(.leading, 52).padding(.bottom, CGFloat.velix.xs)
            case let .ready(size, updated):
                if let onRemove {
                    row("\(size) · updated \(updated)") { RowButton(title: "Remove", danger: true, action: onRemove) }
                } else {
                    row("\(size) · updated \(updated)") { StatusCheck(text: "Ready") }
                }
            case let .update(size):
                row("Update · \(size)") {
                    HStack(spacing: CGFloat.velix.xs) {
                        if let onRemove { RowButton(title: "Remove", danger: true, action: onRemove) }
                        RowButton(title: "Update", action: onAction)
                    }
                }
            case let .available(size):
                row(size) { RowButton(title: "Download", action: onAction) }
            case .failed:
                ListRow(leading: .tile(.map), title: region, subtitle: "Download stopped. Check your connection.",
                        subtitleStyle: Color.velix.danger, subtitleBold: true, divider: divider) {
                    RowButton(title: "Retry", action: onAction)
                }
            }
        }
        .accessibilityElement(children: .contain)
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
