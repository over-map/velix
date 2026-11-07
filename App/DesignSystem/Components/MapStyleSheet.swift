import SwiftUI

/// MapStyleSheet (P2 §08, S1/S7): the two styles of the current ride type and the overlay switches.
struct MapStyleSheet: View {
    enum Style: String { case standard = "Standard", outdoor = "Outdoor", satellite = "Satellite" }
    let rideType: RideType
    @Binding var style: Style
    @Binding var bikeLanes: Bool
    @Binding var transitLines: Bool
    /// Light / Dark / Auto for the map (nil hides the row: gallery samples).
    var appearance: Binding<MapAppearance>?
    /// S1h/i: close button and "Until you close Velix." (nil hides them).
    var onClose: (() -> Void)?

    /// City / Road / Cargo → Standard | Satellite; Gravel / MTB / E-bike → Outdoor | Satellite (BRIEF §8).
    var styles: [Style] { Self.styles(for: rideType) }

    /// Styles offered per ride type (P2 MapStyleSheet, BUILD_PLAN M5).
    nonisolated static func styles(for rideType: RideType) -> [Style] {
        switch rideType {
        case .city, .road, .cargo: [.standard, .satellite]
        case .gravel, .mtb, .ebike: [.outdoor, .satellite]
        }
    }

    var body: some View {
        VelixSheet {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Map").velixType(.title2).foregroundStyle(Color.velix.ink).accessibilityAddTraits(.isHeader)
                    Text("Styles for \(rideType.name)").velixType(VelixType.body.sized(14, lineHeight: 19)).foregroundStyle(Color.velix.ink2)
                }
                Spacer()
                if let onClose { SheetCloseButton(action: onClose) }
            }
            HStack(spacing: CGFloat.velix.s) { ForEach(styles, id: \.self) { styleTile($0) } }
            // Satellite keeps its one (light) look whatever is picked here (Filippo, 7 Nov).
            if let appearance {
                SectionLabel("Light or dark")
                HStack(spacing: CGFloat.velix.xs) {
                    ForEach(MapAppearance.allCases, id: \.self) { a in
                        let on = appearance.wrappedValue == a
                        Button { appearance.wrappedValue = a } label: {
                            Text(a.title).velixType(.label)
                                .foregroundStyle(on ? Color.velix.surface : Color.velix.ink)
                                .frame(maxWidth: .infinity).frame(minHeight: 40)
                                .background(on ? Color.velix.ink : Color.velix.surface, in: Capsule())
                                .overlay { if !on { Capsule().strokeBorder(Color.velix.line, lineWidth: 1) } }
                                .frame(minHeight: CGFloat.velix.touch.min)
                        }
                        .buttonStyle(VelixPressStyle())
                        .accessibilityLabel("Map \(a.title)")
                        .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
                    }
                }
            }
            SectionLabel("Overlays")
            VStack(spacing: 0) {
                overlayRow(icon: VelixIconView(.bike, size: 22), title: "Bike lanes", isOn: $bikeLanes, first: true)
                overlayRow(icon: VelixIconView(.train, size: 22), title: "Train & metro lines", isOn: $transitLines, first: false)
            }
            if onClose != nil {
                Text("Until you close Velix.").velixType(.footnote).foregroundStyle(Color.velix.ink3)
            }
        }
    }

    private func styleTile(_ s: Style) -> some View {
        let isSelected = s == style
        return Button { style = s } label: {
            VStack(alignment: .leading, spacing: 6) {
                StylePreview(style: s)
                    .frame(height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(isSelected ? Color.velix.ink : Color.velix.line, lineWidth: isSelected ? 3 : 1))
                HStack(spacing: 6) {
                    if isSelected { VelixIconView(.check, size: 16) }
                    Text(s.rawValue).velixType(.label)
                }
                .foregroundStyle(Color.velix.ink)
            }
        }
        .buttonStyle(VelixPressStyle())
        .accessibilityLabel("\(s.rawValue) map")
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    private func overlayRow(icon: VelixIconView, title: String, isOn: Binding<Bool>, first: Bool) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: CGFloat.velix.s) {
                icon
                Text(title).velixType(.rowTitle)
            }
            .foregroundStyle(Color.velix.ink)
        }
        .toggleStyle(VelixToggleStyle())
        .padding(.vertical, CGFloat.velix.xs)
        .frame(minHeight: 56)
        .overlay(alignment: .top) { if !first { Rectangle().fill(Color.velix.line).frame(height: 1) } }
    }
}

/// Small map thumbnails for the style tiles (schematic, as in P2).
private struct StylePreview: View {
    let style: MapStyleSheet.Style
    var body: some View {
        Canvas { ctx, size in
            switch style {
            case .standard, .outdoor:
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(style == .outdoor ? Color.velix.mixQuiet.opacity(0.35) : Color.velix.canvas))
                let road = Color.velix.surface
                ctx.fill(Path(CGRect(x: 0, y: size.height * 0.28, width: size.width, height: 6)), with: .color(road))
                ctx.fill(Path(CGRect(x: 0, y: size.height * 0.68, width: size.width, height: 6)), with: .color(road))
                ctx.fill(Path(CGRect(x: size.width * 0.68, y: 0, width: 6, height: size.height)), with: .color(road))
                ctx.fill(Path(CGRect(x: size.width * 0.22, y: 0, width: 4, height: size.height)), with: .color(Color.velix.mixProtected))
                ctx.fill(Path(roundedRect: CGRect(x: size.width * 0.44, y: size.height * 0.4, width: size.width * 0.18, height: size.height * 0.22), cornerRadius: 3),
                         with: .color(Color.velix.mixQuiet))
            case .satellite:
                // A photo-like tile (7 Nov: imagery from Esri / EOX): fields and woods in patches, a pale road on top.
                let w = size.width, h = size.height
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color.velix.mixQuiet.opacity(0.85)))
                let patches: [(CGRect, Color)] = [
                    (CGRect(x: 0, y: 0, width: w * 0.45, height: h * 0.5), Color.velix.mixUnpaved.opacity(0.7)),
                    (CGRect(x: w * 0.55, y: h * 0.1, width: w * 0.45, height: h * 0.35), Color.velix.mixProtected.opacity(0.55)),
                    (CGRect(x: w * 0.1, y: h * 0.6, width: w * 0.35, height: h * 0.4), Color.velix.ink3.opacity(0.45)),
                    (CGRect(x: w * 0.6, y: h * 0.62, width: w * 0.4, height: h * 0.38), Color.velix.mixUnpaved.opacity(0.45)),
                ]
                for (r, c) in patches { ctx.fill(Path(r), with: .color(c)) }
                ctx.fill(Path(CGRect(x: 0, y: h * 0.52, width: w, height: 5)), with: .color(Color.velix.surface))
                ctx.fill(Path(CGRect(x: w * 0.5, y: 0, width: 4, height: h)), with: .color(Color.velix.surface.opacity(0.85)))
            }
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    MapStyleSheet(rideType: .city, style: .constant(.standard), bikeLanes: .constant(true), transitLines: .constant(false))
        .padding().background(Color.velix.canvas)
}
