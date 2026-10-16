import SwiftUI

/// WhyThisRoute (P2 §08, S3): collapsed link; expanded list of hazards on your route and roads avoided.
/// Same items as the map (striped tubes = on your route, dashed lilac = avoided), so the map lines have an accessible twin.
struct WhyThisRoute: View {
    struct Hazard: Hashable { var type: HazardType; var subtitle: String; var count: Int? }
    struct Avoided: Hashable { var name: String; var reason: String }

    @Binding var expanded: Bool
    var hazards: [Hazard] = []
    var avoided: [Avoided] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { expanded.toggle() } label: {
                HStack(spacing: 4) {
                    Text("Why this route").velixType(.label)
                    VelixIconView(expanded ? .chevronDown : .chevronRight, size: 18)
                }
                .foregroundStyle(Color.velix.ink)
                .frame(height: CGFloat.velix.touch.min)
            }
            .buttonStyle(.plain)
            .accessibilityValue(expanded ? "Expanded" : "Collapsed")
            if expanded {
                SectionLabel("On your route")
                ForEach(hazards, id: \.self) { HazardRow(hazard: $0) }
                SectionLabel("Avoided").padding(.top, CGFloat.velix.s)
                ForEach(avoided, id: \.self) { AvoidedRow(avoided: $0) }
            }
        }
    }
}

/// HazardRow: coral glyph tile, hazard name, where, how many.
struct HazardRow: View {
    let hazard: WhyThisRoute.Hazard
    var body: some View {
        HStack(spacing: CGFloat.velix.s) {
            HazardMarker(type: hazard.type, style: .tile)
            VStack(alignment: .leading, spacing: 0) {
                Text(hazard.type.title).velixType(.rowTitle).foregroundStyle(Color.velix.ink)
                Text(hazard.subtitle).velixType(.rowSubtitle).foregroundStyle(Color.velix.ink2)
            }
            Spacer(minLength: 0)
            if let count = hazard.count { Text("\(count)×").velixType(.label).foregroundStyle(Color.velix.ink2) }
        }
        .padding(.vertical, CGFloat.velix.s)
        .frame(minHeight: 64)
        .overlay(alignment: .top) { Rectangle().fill(Color.velix.line).frame(height: 1) }
        .accessibilityElement(children: .combine)
    }
}

/// AvoidedRow: dashed lilac line, street name, the reason it was avoided.
struct AvoidedRow: View {
    let avoided: WhyThisRoute.Avoided
    var body: some View {
        HStack(spacing: CGFloat.velix.s) {
            AvoidedLineGlyph().frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 0) {
                Text(avoided.name).velixType(.rowTitle).foregroundStyle(Color.velix.ink)
                Text("✕ \(avoided.reason)").velixType(VelixType.rowSubtitle).fontWeight(.bold).foregroundStyle(Color.velix.avoidedInk)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, CGFloat.velix.s)
        .frame(minHeight: 64)
        .overlay(alignment: .top) { Rectangle().fill(Color.velix.line).frame(height: 1) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Avoided \(avoided.name): \(avoided.reason)")
    }
}

/// The avoided-road key: dashed lilac, as drawn in the P2 rows.
struct AvoidedLineGlyph: View {
    var body: some View {
        Canvas { ctx, size in
            // Three short dashes, as the P2 row key.
            for i in 0 ..< 3 {
                let x = 2 + Double(i) * 10
                ctx.fill(Path(CGRect(x: x, y: size.height / 2 - 1.5, width: 6, height: 3)), with: .color(Color.velix.avoided))
            }
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    VStack(alignment: .leading) {
        WhyThisRoute(expanded: .constant(false))
        WhyThisRoute(expanded: .constant(true),
                     hazards: [.init(type: .tram, subtitle: "Viale Romagna", count: 1), .init(type: .door, subtitle: "Via Pascoli, 150 m", count: nil)],
                     avoided: [.init(name: "Corso Buenos Aires", reason: "Rails along lane"), .init(name: "Via Plinio", reason: "Cobbles 300 m")])
    }
    .padding().background(Color.velix.canvas)
}
