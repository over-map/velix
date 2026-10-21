import SwiftUI

/// Round 52 pt map control (MapButton, RecenterButton; P2 §08).
private struct RoundMapButton<Content: View>: View {
    var active = false
    let label: String
    let action: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        Button(action: action) {
            content
                .frame(width: 52, height: 52)
                .foregroundStyle(active ? Color.velix.surface : Color.velix.ink)
                .background(active ? Color.velix.ink : Color.velix.surface, in: Circle())
                .velixElevation(active ? VelixElevations.e0 : VelixElevations.e1, in: Circle())
        }
        .buttonStyle(VelixPressStyle())
        .accessibilityLabel(label)
    }
}

/// MapButton: map styles and overlays (set only before riding). Active while the MapStyleSheet is open.
struct MapButton: View {
    var active = false
    var action: () -> Void = {}
    var body: some View {
        RoundMapButton(active: active, label: "Map styles and overlays", action: action) { VelixIconView(.layers, size: 24) }
    }
}

/// RecenterButton: locate (default) or following (accent arrow with ink outline). `riding` is the 60 pt S4j button
/// with locate-fixed (P5: nothing smaller than 60 pt while riding).
struct RecenterButton: View {
    var following = false
    var riding = false
    var action: () -> Void = {}
    var body: some View {
        if riding {
            Button(action: action) {
                VelixIconView(.locateFixed, size: 26)
                    .frame(width: 60, height: 60)
                    .foregroundStyle(Color.velix.ink)
                    .background(Color.velix.surface, in: Circle())
                    .velixElevation(VelixElevations.e1, in: Circle())
            }
            .buttonStyle(VelixPressStyle())
            .accessibilityLabel("Recenter on your location")
        } else {
            mapButton
        }
    }

    private var mapButton: some View {
        RoundMapButton(label: following ? "Following your position" : "Recenter on your location", action: action) {
            if following {
                ZStack {
                    VelixIconView(.navigation2, size: 24).foregroundStyle(Color.velix.casing)
                    // Filled accent arrow inside the ink outline (P2: fill accent, stroke casing).
                    NavigationArrow().fill(Color.velix.accent).frame(width: 12, height: 15).offset(y: 1)
                }
            } else {
                VelixIconView(.locate, size: 24)
            }
        }
    }
}

/// The lucide navigation-2 arrow as a fillable shape (24 pt grid: 12,2 → 19,21 → 12,17 → 5,21).
struct NavigationArrow: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.midX, y: r.minY + r.height * 0.79))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

#Preview {
    HStack(spacing: 14) { MapButton(); MapButton(active: true); RecenterButton(); RecenterButton(following: true); RecenterButton(riding: true) }
        .padding().background(Color.velix.canvas)
}
