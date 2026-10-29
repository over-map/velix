import SwiftUI
import UIKit

/// Images the map styles reference, drawn at runtime instead of a sprite atlas (docs/DECISIONS.md, M5): markers reuse
/// the M4 components, patterns and tiles follow P3 render.js. Names end in `-day` / `-night`.
@MainActor
enum MapImages {
    /// Avoided-road tag texts by id, set with the route (`avoided-<id>-<mode>`).
    static var avoidedTexts: [String: String] = [:]

    static func image(named name: String) -> UIImage? {
        var parts = name.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        let mode: MapMode = parts.last == "night" ? .night : .day
        if parts.last == "day" || parts.last == "night" { parts.removeLast() }
        let pal = mode == .day ? MapPalette.day : MapPalette.night
        switch parts.first {
        case "trees": return trees(pal)
        case "hz" where parts.count == 2 && parts[1] == "stripe": return stripe(pal)
        case "hz": return HazardType(rawValue: parts.dropFirst().joined(separator: "-")).flatMap { swiftUI(HazardMarker(type: $0, style: .map), mode) }
        case "cnt": return Int(parts.last ?? "").flatMap { swiftUI(HazardMarker(style: .cluster($0)), mode) }
        case "poi": return parts.count >= 2 ? poi(parts[1], pal) : nil
        case "metro": return parts.count >= 2 ? metroTile(parts.dropFirst().joined(separator: "-"), pal) : nil
        case "rail": return railTile(pal)
        case "start": return start(pal)
        case "end": return end(pal)
        case "puck": return puck(CGFloat(Int(parts.last ?? "34") ?? 34), pal)
        case "avoided": return avoidedTexts[parts.dropFirst().joined(separator: "-")].flatMap { swiftUI(AvoidedTag(reason: $0), mode) }
        case "ev": return euroVelo(parts.dropFirst().joined(separator: "-"))
        case "key": return parts.count >= 2 ? Int(parts[1]).flatMap { swiftUI(RouteKeyTile(number: $0, focused: parts.last == "sel"), mode) } : nil
        default: return nil
        }
    }

    // MARK: SwiftUI components

    private static func swiftUI(_ view: some View, _ mode: MapMode) -> UIImage? {
        let r = ImageRenderer(content: view.environment(\.colorScheme, mode == .night ? .dark : .light).padding(1))
        r.scale = UIScreen.main.scale
        return r.uiImage
    }

    private static func draw(_ size: CGSize, _ body: (CGContext) -> Void) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        return UIGraphicsImageRenderer(size: size, format: format).image { body($0.cgContext) }
    }

    // MARK: Patterns

    /// Tree texture (P3: dots in woods z14+, parks z15+), a 24 pt tile of jittered dots.
    private static func trees(_ p: MapPalette) -> UIImage {
        draw(CGSize(width: 24, height: 24)) { c in
            c.setFillColor(p.woodDot.cgColor)
            for (x, y, r) in [(4.0, 5.0, 1.6), (15.0, 3.0, 1.3), (10.0, 13.0, 1.7), (20.0, 12.0, 1.4), (5.0, 20.0, 1.4), (17.0, 21.0, 1.6)] {
                c.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
            }
        }
    }

    /// Hazard tube stripes: P3 20 px tile, 45°, hazard on hazard ring.
    private static func stripe(_ p: MapPalette) -> UIImage {
        draw(CGSize(width: 10, height: 10)) { c in
            c.setFillColor(p.hazardRing.cgColor); c.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
            c.setFillColor(p.hazard.cgColor)
            c.move(to: .zero); c.addLine(to: CGPoint(x: 5, y: 0)); c.addLine(to: CGPoint(x: 0, y: 5)); c.closePath()
            c.move(to: CGPoint(x: 10, y: 0)); c.addLine(to: CGPoint(x: 10, y: 5)); c.addLine(to: CGPoint(x: 5, y: 10))
            c.addLine(to: CGPoint(x: 0, y: 10)); c.closePath(); c.fillPath()
        }
    }

    // MARK: Tiles and markers (P3 render.js)

    /// POI disc r 6.5 with the category glyph (bike: "P").
    private static func poi(_ cat: String, _ p: MapPalette) -> UIImage {
        let r: CGFloat = 6.5, size = CGSize(width: r * 2 + 2, height: r * 2 + 2)
        let colour = cat == "bike" ? p.prot : (p.poi[cat] ?? p.poi["generic"] ?? p.prot)
        return draw(size) { c in
            c.setAlpha(p.poiAlpha)
            let disc = CGRect(x: 1, y: 1, width: r * 2, height: r * 2)
            c.setFillColor(colour.cgColor); c.fillEllipse(in: disc)
            c.setStrokeColor(p.halo.cgColor); c.setLineWidth(1.2); c.strokeEllipse(in: disc)
            if cat == "bike" {
                text("P", size: 9, bold: true, colour: .white, center: CGPoint(x: size.width / 2, y: size.height / 2))
            } else if let glyph = VelixGlyph(rawValue: "glyph-poi-\(cat)"), let img = UIImage(named: glyph.rawValue) {
                img.withTintColor(p.glyph).draw(in: disc.insetBy(dx: r * 0.38, dy: r * 0.38))
            }
        }
    }

    /// Metro station: one rounded tile per line in its colour family, with the line number (P3 r 5).
    /// `tiles` is the overlay's "M1.red.0,M3.yellow.0" (ref, family, alt).
    private static func metroTile(_ tiles: String, _ p: MapPalette) -> UIImage {
        let lines = tiles.split(separator: ",").map { $0.split(separator: ".").map(String.init) }.filter { $0.count == 3 }
        let rr: CGFloat = 5, step = rr * 2.6
        let size = CGSize(width: CGFloat(max(lines.count, 1)) * step + 2, height: rr * 2.3 + 3)
        return draw(size) { _ in
            for (i, l) in lines.enumerated() {
                let fam = MapPalette.metroFamilies[l[1]] ?? MapPalette.metroFamilies["grey"]!
                let alt = l[2] == "1"
                let rect = CGRect(x: 1 + CGFloat(i) * step + (step - rr * 2.3) / 2, y: 1.5, width: rr * 2.3, height: rr * 2.3)
                let path = UIBezierPath(roundedRect: rect, cornerRadius: rr * 0.55)
                (alt ? fam.alt : fam.main).setFill(); path.fill()
                // Light tiles (yellow) need the dark ring to read on paper (P3: M3).
                (l[1] == "yellow" ? p.casing : p.halo).setStroke(); path.lineWidth = 1.4; path.stroke()
                let number = l[0].filter(\.isNumber)
                text(number.isEmpty ? String(l[0].prefix(1)) : number, size: rr * 1.25, bold: true,
                     colour: alt ? fam.altInk : fam.ink, center: CGPoint(x: rect.midX, y: rect.midY))
            }
        }
    }

    /// Rail station: 14 pt tile in the train colour with "FS".
    private static func railTile(_ p: MapPalette) -> UIImage {
        draw(CGSize(width: 16, height: 16)) { _ in
            let path = UIBezierPath(roundedRect: CGRect(x: 1, y: 1, width: 14, height: 14), cornerRadius: 3.5)
            p.train.setFill(); path.fill(); p.halo.setStroke(); path.lineWidth = 1.4; path.stroke()
            text("FS", size: 9, bold: true, colour: .white, center: CGPoint(x: 8, y: 8.5))
        }
    }

    /// Start: white disc r 8, 3 pt casing ring (scaled down by zoom in the style).
    private static func start(_ p: MapPalette) -> UIImage {
        draw(CGSize(width: 22, height: 22)) { c in
            let r = CGRect(x: 3, y: 3, width: 16, height: 16)
            c.setFillColor(UIColor.white.cgColor); c.fillEllipse(in: r)
            c.setStrokeColor(p.casing.cgColor); c.setLineWidth(3); c.strokeEllipse(in: r)
        }
    }

    /// End: casing disc r 11, white 2 pt ring, accent core at 0.42 R.
    private static func end(_ p: MapPalette) -> UIImage {
        draw(CGSize(width: 26, height: 26)) { c in
            let r = CGRect(x: 2, y: 2, width: 22, height: 22)
            c.setFillColor(p.casing.cgColor); c.fillEllipse(in: r)
            c.setStrokeColor(UIColor.white.cgColor); c.setLineWidth(2); c.strokeEllipse(in: r)
            c.setFillColor(p.accent.cgColor); c.fillEllipse(in: r.insetBy(dx: 11 * 0.58, dy: 11 * 0.58))
        }
    }

    /// Location puck with heading cone (radius 22 / 34 / 46 by zoom), pointing up; the style rotates it.
    private static func puck(_ cone: CGFloat, _ p: MapPalette) -> UIImage {
        let size = CGSize(width: cone * 2, height: cone * 2), o = CGPoint(x: cone, y: cone)
        return draw(size) { c in
            c.move(to: o); c.addArc(center: o, radius: cone, startAngle: -.pi / 2 - 0.5, endAngle: -.pi / 2 + 0.5, clockwise: false); c.closePath()
            c.setFillColor(p.accent.withAlphaComponent(0.42).cgColor); c.fillPath()
            c.setFillColor(UIColor.white.cgColor); c.fillEllipse(in: CGRect(x: o.x - 12, y: o.y - 12, width: 24, height: 24))
            c.setFillColor(p.accent.cgColor); c.fillEllipse(in: CGRect(x: o.x - 10, y: o.y - 10, width: 20, height: 20))
            c.setStrokeColor(p.casing.cgColor); c.setLineWidth(3); c.strokeEllipse(in: CGRect(x: o.x - 10, y: o.y - 10, width: 20, height: 20))
            c.setFillColor(p.accentInk.cgColor)
            c.move(to: CGPoint(x: o.x, y: o.y - 5)); c.addLine(to: CGPoint(x: o.x + 4, y: o.y + 4))
            c.addLine(to: CGPoint(x: o.x, y: o.y + 2)); c.addLine(to: CGPoint(x: o.x - 4, y: o.y + 4)); c.closePath(); c.fillPath()
        }
    }

    /// EuroVelo badge: navy tile, khaki "EV" + paper number (P3 spec), 24 pt tall.
    private static func euroVelo(_ ref: String) -> UIImage {
        let num = ref.uppercased().replacingOccurrences(of: "EV", with: "")
        return draw(CGSize(width: 40, height: 24)) { _ in
            let path = UIBezierPath(roundedRect: CGRect(x: 1, y: 1, width: 38, height: 22), cornerRadius: 6)
            UIColor(Color.velix.paletteNavy).setFill(); path.fill()
            UIColor(Color.velix.paletteKhaki).setStroke(); path.lineWidth = 1.5; path.stroke()
            text("EV", size: 9, bold: true, colour: UIColor(Color.velix.paletteKhaki), center: CGPoint(x: 13, y: 12))
            text(num, size: 11, bold: true, colour: UIColor(Color.velix.palettePaper), center: CGPoint(x: 27, y: 12))
        }
    }

    private static func text(_ s: String, size: CGFloat, bold: Bool, colour: UIColor, center: CGPoint) {
        let font = UIFont(name: bold ? "AtkinsonHyperlegible-Bold" : "AtkinsonHyperlegible-Regular", size: size) ?? .systemFont(ofSize: size)
        let a: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: colour]
        let sz = (s as NSString).size(withAttributes: a)
        (s as NSString).draw(at: CGPoint(x: center.x - sz.width / 2, y: center.y - sz.height / 2), withAttributes: a)
    }
}
