import SwiftUI

/// HazardMarker (P2 §08 + P3 render.js):
///  - `.tile`: 32 pt coral tile with a surface ring (lists, legends);
///  - `.map`: map marker, coral rounded tile with ink ring and a pointer (route overview from zoom 15, riding);
///  - `.cluster(n)`: nearby hazards merged below zoom 15, the same tile with a count (docs/DECISIONS.md, 15 Oct).
struct HazardMarker: View {
    enum Style: Equatable { case tile, map, cluster(Int) }
    var type: HazardType = .tram
    var style: Style = .tile

    var body: some View {
        switch style {
        case .tile:
            VelixIconView(type.glyph, size: 20)
                .foregroundStyle(Color.velix.hazardInk)
                .frame(width: 32, height: 32)
                .background(Color.velix.hazard, in: RoundedRectangle(cornerRadius: CGFloat.velix.radius.chip))
                .overlay(RoundedRectangle(cornerRadius: CGFloat.velix.radius.chip + 2).stroke(Color.velix.surface, lineWidth: 2).padding(-1))
                .accessibilityLabel(type.title)
        case .map:
            pin { VelixIconView(type.glyph, size: 18).foregroundStyle(Color.velix.hazardInk) }
                .accessibilityLabel(type.title)
        case let .cluster(n):
            pin { Text("\(n)").velixType(.cardTitle).foregroundStyle(Color.velix.hazardInk) }
                .accessibilityLabel("\(n) hazards here")
        }
    }

    private func pin(@ViewBuilder _ content: () -> some View) -> some View {
        VStack(spacing: -1) {
            content()
                .frame(width: 28, height: 28)
                .background(Color.velix.hazard, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.velix.casing, lineWidth: 2))
            Triangle().fill(Color.velix.casing).frame(width: 10, height: 6)
        }
    }
}

/// AvoidedTag (P2 §08): the reason on an avoided road, on the map ("✕ Cobbles 300 m").
struct AvoidedTag: View {
    let reason: String
    var body: some View {
        Text("✕ \(reason)")
            .velixType(VelixType.label.sized(13, lineHeight: 16))
            .foregroundStyle(Color.velix.avoidedInk)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(Color.velix.surface, in: RoundedRectangle(cornerRadius: CGFloat.velix.radius.chip))
            .velixElevation(VelixElevations.e1, in: RoundedRectangle(cornerRadius: CGFloat.velix.radius.chip))
    }
}

/// HazardTube swatch: 45° stripes, hazard / casing, 5 pt each (tokens → pattern.hazardTube). The map draws the
/// same pattern along the route in M5.
struct HazardTubeSwatch: View {
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color.velix.casing))
            ctx.stroke(MixSwatch.hatch(size, period: 10), with: .color(Color.velix.hazard), lineWidth: 5)
        }
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }
}

struct Triangle: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY)); p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

#Preview {
    VStack(spacing: 16) {
        HStack { ForEach(HazardType.allCases, id: \.self) { HazardMarker(type: $0) } }
        HStack { HazardMarker(type: .cobbles, style: .map); HazardMarker(style: .cluster(5)) }
        HStack { AvoidedTag(reason: "Rails along lane"); AvoidedTag(reason: "Cobbles 300 m") }
        HazardTubeSwatch().frame(width: 120, height: 10)
    }
    .padding().background(Color.velix.canvas)
}
