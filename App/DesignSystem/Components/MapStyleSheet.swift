import SwiftUI

/// MapStyleSheet (P2 §08, S1/S7): the two styles of the current ride type and the overlay switches.
struct MapStyleSheet: View {
    enum Style: String { case standard = "Standard", outdoor = "Outdoor", satellite = "Satellite" }
    let rideType: RideType
    @Binding var style: Style
    @Binding var bikeLanes: Bool
    @Binding var transitLines: Bool

    /// City / Road / Cargo → Standard | Satellite; Gravel / MTB / E-bike → Outdoor | Satellite (BRIEF §8).
    var styles: [Style] {
        switch rideType {
        case .city, .road, .cargo: [.standard, .satellite]
        case .gravel, .mtb, .ebike: [.outdoor, .satellite]
        }
    }

    var body: some View {
        VelixSheet {
            VStack(alignment: .leading, spacing: 0) {
                Text("Map").velixType(.title2).foregroundStyle(Color.velix.ink).accessibilityAddTraits(.isHeader)
                Text("Styles for \(rideType.name)").velixType(VelixType.body.sized(14, lineHeight: 19)).foregroundStyle(Color.velix.ink2)
            }
            HStack(spacing: CGFloat.velix.s) { ForEach(styles, id: \.self) { styleTile($0) } }
            SectionLabel("Overlays")
            VStack(spacing: 0) {
                overlayRow(icon: VelixIconView(.bike, size: 22), title: "Bike lanes", isOn: $bikeLanes, first: true)
                overlayRow(icon: VelixIconView(.train, size: 22), title: "Train & metro lines", isOn: $transitLines, first: false)
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
        .accessibilityLabel(s.rawValue)
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

/// Small map thumbnails for the style tiles (schematic, as in P2; real map previews come with M5).
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
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color.velix.surface2))
                var stripes = Path()
                stride(from: -size.height, to: size.width, by: 9).forEach { x in
                    stripes.move(to: CGPoint(x: x, y: size.height)); stripes.addLine(to: CGPoint(x: x + size.height, y: 0))
                }
                ctx.stroke(stripes, with: .color(Color.velix.line), lineWidth: 1)
                ctx.draw(Text("Imagery TBD").font(Font.velix.caption).foregroundColor(Color.velix.ink2),
                         at: CGPoint(x: size.width / 2, y: size.height / 2))
            }
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    MapStyleSheet(rideType: .city, style: .constant(.standard), bikeLanes: .constant(true), transitLines: .constant(false))
        .padding().background(Color.velix.canvas)
}
