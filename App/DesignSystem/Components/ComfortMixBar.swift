import SwiftUI

/// ComfortMixBar (P2 §08): share of the route per comfort category, in the fixed design order, with patterns so it
/// reads without colour (painted ticks, cobble hatch, unpaved dots). Large 12 pt (selected card) or compact 8 pt.
struct ComfortMixBar: View {
    enum Size { case large, compact }
    let mix: [MixCategory: Double]
    var size: Size = .large

    private var height: CGFloat { size == .large ? 12 : 8 }
    private var parts: [(MixCategory, Double)] {
        let total = mix.values.reduce(0, +)
        guard total > 0 else { return [] }
        return MixCategory.allCases.compactMap { c in (mix[c] ?? 0) > 0 ? (c, (mix[c] ?? 0) / total) : nil }
    }

    var body: some View {
        GeometryReader { geo in
            let gaps = CGFloat(max(parts.count - 1, 0)) * 2
            HStack(spacing: 2) {
                ForEach(parts, id: \.0) { c, share in
                    MixSwatch(category: c).frame(width: max(2, (geo.size.width - gaps) * share))
                }
            }
        }
        .frame(height: height)
        .clipShape(Capsule())
        .accessibilityElement()
        .accessibilityLabel("Comfort mix")
        .accessibilityValue(parts.map { "\($0.0.label) \(Int(($0.1 * 100).rounded())) percent" }.joined(separator: ", "))
    }
}

/// Legend under the mix bar: swatch, label, distance, two columns in design order.
struct ComfortMixLegend: View {
    let meters: [MixCategory: Double]
    /// P2 legend: always km, one decimal ("0.6 km").
    static func km(_ m: Double) -> String { String(format: "%.1f km", m / 1000) }
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible())], alignment: .leading, spacing: CGFloat.velix.xs) {
            ForEach(MixCategory.allCases.filter { (meters[$0] ?? 0) > 0 }, id: \.self) { c in
                HStack(spacing: CGFloat.velix.xs) {
                    MixSwatch(category: c).frame(width: 16, height: 16).clipShape(RoundedRectangle(cornerRadius: 3))
                    Text(c.label).velixType(.detail).foregroundStyle(Color.velix.ink)
                    Spacer(minLength: 0)
                    Text(Self.km(meters[c] ?? 0)).velixType(.detail).monospacedDigit().foregroundStyle(Color.velix.ink2)
                }
            }
        }
    }
}

extension MixCategory {
    /// Legend copy (P2 §08 ComfortMixBar).
    var label: String {
        switch self {
        case .protected: "Protected"
        case .painted: "Painted lane"
        case .quiet: "Quiet street"
        case .mixed: "Mixed traffic"
        case .cobbles: "Cobbles"
        case .unpaved: "Unpaved"
        }
    }
}

/// One mix category's fill, with its pattern (velix-tokens.json → pattern).
struct MixSwatch: View {
    let category: MixCategory
    var body: some View {
        Canvas { ctx, size in
            let rect = CGRect(origin: .zero, size: size)
            switch category {
            case .protected: ctx.fill(Path(rect), with: .color(Color.velix.mixProtected))
            case .quiet: ctx.fill(Path(rect), with: .color(Color.velix.mixQuiet))
            case .mixed: ctx.fill(Path(rect), with: .color(Color.velix.mixMixed))
            case .painted:
                // solid with 2 pt ticks every 8 pt
                ctx.fill(Path(rect), with: .color(Color.velix.mixPainted))
                for x in stride(from: 6.0, to: size.width, by: 8) {
                    ctx.fill(Path(CGRect(x: x, y: 0, width: 2, height: size.height)), with: .color(Color.velix.mixPaintedTick))
                }
            case .cobbles:
                // 45° hatch, 3 pt mixCobbles / 3 pt mixCobblesAlt (period 6 pt across the stripes)
                ctx.fill(Path(rect), with: .color(Color.velix.mixCobblesAlt))
                ctx.stroke(Self.hatch(size, period: 6), with: .color(Color.velix.mixCobbles), lineWidth: 3)
            case .unpaved:
                // base + 1.4 pt dots on a 5 pt grid
                ctx.fill(Path(rect), with: .color(Color.velix.mixUnpaved))
                for x in stride(from: 2.5, to: size.width, by: 5) {
                    for y in stride(from: 2.5, to: size.height, by: 5) {
                        ctx.fill(Path(ellipseIn: CGRect(x: x - 1.4, y: y - 1.4, width: 2.8, height: 2.8)), with: .color(Color.velix.mixUnpavedDot))
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }

    /// 45° lines `period` pt apart, measured across the stripes.
    static func hatch(_ size: CGSize, period: Double) -> Path {
        var p = Path()
        for x in stride(from: -size.height, to: size.width + size.height, by: period * 2.squareRoot()) {
            p.move(to: CGPoint(x: x, y: size.height)); p.addLine(to: CGPoint(x: x + size.height, y: 0))
        }
        return p
    }
}

#Preview {
    let mix: [MixCategory: Double] = [.protected: 1600, .painted: 1100, .quiet: 1100, .mixed: 600, .cobbles: 500, .unpaved: 400]
    VStack(alignment: .leading, spacing: 16) {
        ComfortMixBar(mix: mix)
        ComfortMixBar(mix: mix, size: .compact)
        ComfortMixLegend(meters: mix)
    }
    .padding().background(Color.velix.canvas)
}
