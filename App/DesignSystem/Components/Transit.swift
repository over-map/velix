import SwiftUI

/// Metro line badge (P2 TransitSuggestionRow): the line's colour family and its ink. M8 maps GTFS lines to families.
struct MetroBadge: View, Hashable {
    let name: String
    let color: Color
    let ink: Color
    var body: some View {
        Text(name).velixType(VelixType.headline.sized(13, lineHeight: 15))
            .foregroundStyle(ink)
            .frame(width: 28, height: 28)
            .background(color, in: RoundedRectangle(cornerRadius: 6))
            .accessibilityLabel("Metro \(name)")
    }
    static let m1 = MetroBadge(name: "M1", color: Color.velix.transitMetroRed, ink: Color.velix.transitMetroRedInk)
}

/// Mode of a transit-trip leg or suggestion.
enum TransitMode: Hashable {
    case ride, train, metro(MetroBadge)
}

/// 40 pt leg / suggestion tile: bike, train glyph or metro badge on surface-2.
struct TransitModeTile: View {
    let mode: TransitMode
    var body: some View {
        Group {
            switch mode {
            case .ride: VelixIconView(.bike, size: 24)
            case .train: VelixIconView(.train, size: 24)
            case let .metro(badge): badge
            }
        }
        .foregroundStyle(Color.velix.ink)
        .frame(width: 40, height: 40)
        .background(Color.velix.surface2, in: RoundedRectangle(cornerRadius: 10))
    }
}

/// TransitSuggestionRow (P2 §08, S3): "Bike + train · 52 min, 26 min faster than Best" under the route cards.
struct TransitSuggestionRow: View {
    let mode: TransitMode
    let title: String
    let subtitle: String
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            HStack(spacing: CGFloat.velix.s) {
                TransitModeTile(mode: mode)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).velixType(.rowTitle).foregroundStyle(Color.velix.ink)
                    Text(subtitle).velixType(.rowSubtitle).foregroundStyle(Color.velix.ink2)
                }
                Spacer(minLength: 0)
                VelixIconView(.chevronRight, size: 20).foregroundStyle(Color.velix.ink)
            }
            .padding(.horizontal, CGFloat.velix.s).padding(.vertical, 10)
        }
        .buttonStyle(SurfaceRowStyle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// Bordered surface row that turns surface-2 while pressed (P2 "Pressed").
struct SurfaceRowStyle: ButtonStyle {
    var pressed = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed || pressed ? Color.velix.surface2 : Color.velix.surface,
                        in: RoundedRectangle(cornerRadius: CGFloat.velix.radius.card))
            .overlay(RoundedRectangle(cornerRadius: CGFloat.velix.radius.card).strokeBorder(Color.velix.line, lineWidth: 1))
    }
}

/// TripBar (P2 §08): ride / wait / transit segments in proportion to their minutes, labelled underneath.
struct TripBar: View {
    enum Kind: Hashable { case ride, wait, train, metro(Color) }
    struct Segment: Hashable { var kind: Kind; var minutes: Int; var label: String }
    let segments: [Segment]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            proportional(height: 12) { s in
                switch s.kind {
                case .ride: Capsule().fill(Color.velix.accent).overlay(Capsule().strokeBorder(Color.velix.casing, lineWidth: 1.5))
                case .wait: Capsule().fill(Color.velix.surface2)
                case .train: TransitDashes(color: Color.velix.transitTrain).clipShape(Capsule())
                case let .metro(c): Capsule().fill(c)
                }
            }
            proportional(height: 15) { s in
                Text(s.label).velixType(VelixType.body.sized(12, lineHeight: 15)).foregroundStyle(Color.velix.ink2)
                    .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(segments.map(\.label).joined(separator: ", "))
    }

    private func proportional(height: CGFloat, @ViewBuilder _ content: @escaping (Segment) -> some View) -> some View {
        GeometryReader { geo in
            let total = CGFloat(max(segments.reduce(0) { $0 + $1.minutes }, 1))
            let free = geo.size.width - CGFloat(segments.count - 1) * 3
            HStack(spacing: 3) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, s in
                    content(s).frame(width: free * CGFloat(s.minutes) / total)
                }
            }
        }
        .frame(height: height)
    }
}

/// Transit leg fill: dash 8 / gap 2 on surface (P2 TripBar train segment).
struct TransitDashes: View {
    let color: Color
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color.velix.surface))
            for x in stride(from: 0.0, to: size.width, by: 10) {
                ctx.fill(Path(CGRect(x: x, y: 0, width: 8, height: size.height)), with: .color(color))
            }
        }
        .accessibilityHidden(true)
    }
}

/// TransitLegList (P2 §08): one row per leg, tile + what to do + detail.
struct TransitLegList: View {
    struct Leg: Hashable { var mode: TransitMode; var title: String; var detail: String }
    let legs: [Leg]
    var body: some View {
        VStack(spacing: 0) {
            ForEach(legs, id: \.self) { leg in
                HStack(spacing: CGFloat.velix.s) {
                    TransitModeTile(mode: leg.mode)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(leg.title).velixType(.rowTitle).foregroundStyle(Color.velix.ink)
                        Text(leg.detail).velixType(.rowSubtitle).foregroundStyle(Color.velix.ink2)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, CGFloat.velix.xs)
                .frame(minHeight: 56)
                .overlay(alignment: .top) { Rectangle().fill(Color.velix.line).frame(height: 1) }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// TransitCard (P2 §08, S3): the bike + transit option, with the trip bar, next departures, legs and the ticket link.
struct TransitCard: View {
    struct Model {
        var title: String
        var subtitle: String
        var minutes: Int
        var segments: [TripBar.Segment]
        var departures: [String]
        var legs: [TransitLegList.Leg]
        var ticketsLabel: String?
    }
    let model: Model
    @Binding var selectedDeparture: Int
    var onTickets: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: CGFloat.velix.s) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(model.title).velixType(.cardTitle).foregroundStyle(Color.velix.ink)
                    Text(model.subtitle).velixType(VelixType.body.sized(13, lineHeight: 17)).foregroundStyle(Color.velix.ink3)
                }
                Spacer(minLength: CGFloat.velix.xs)
                Text("\(model.minutes) min").velixType(.numberL).foregroundStyle(Color.velix.ink)
            }
            TripBar(segments: model.segments)
            HStack(spacing: CGFloat.velix.xs) {
                SectionLabel("Next trains")
                ForEach(Array(model.departures.enumerated()), id: \.offset) { i, time in
                    Button { selectedDeparture = i } label: {
                        Text(time).velixType(.label).monospacedDigit()
                            .foregroundStyle(i == selectedDeparture ? Color.velix.surface : Color.velix.ink)
                            .padding(.horizontal, CGFloat.velix.s).frame(height: 36)
                            .background(i == selectedDeparture ? Color.velix.ink : Color.velix.surface2,
                                        in: RoundedRectangle(cornerRadius: CGFloat.velix.radius.chip))
                            .frame(minHeight: CGFloat.velix.touch.min)
                    }
                    .buttonStyle(VelixPressStyle())
                    .accessibilityLabel("Train at \(time)")
                    .accessibilityAddTraits(i == selectedDeparture ? .isSelected : [])
                }
            }
            TransitLegList(legs: model.legs)
            if let tickets = model.ticketsLabel {
                Button(action: onTickets) {
                    HStack(spacing: 6) {
                        Text(tickets).underline()
                        VelixIconView(.externalLink, size: 16)
                    }
                    .velixType(.label).foregroundStyle(Color.velix.ink)
                    .frame(minHeight: CGFloat.velix.touch.min)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(.isLink)
            }
        }
        .padding(.horizontal, 14).padding(.top, CGFloat.velix.s).padding(.bottom, 4)
        .background(Color.velix.surface, in: RoundedRectangle(cornerRadius: CGFloat.velix.radius.card))
        .overlay(RoundedRectangle(cornerRadius: CGFloat.velix.radius.card).strokeBorder(Color.velix.ink, lineWidth: 2))
        .velixElevation(VelixElevations.e2)
    }
}

/// OnTrainCard (P2 §08, S5): on the train, when to get off, the next stop and where the bike carriages are.
struct OnTrainCard: View {
    var minutes: String
    var station: String
    var arrival: String
    var nextStop: String
    var thenStop: String
    /// Carriages from the front; true where bikes go.
    var bikeCarriages: [Bool]
    var note: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Get off in").velixType(.ridingLabel).foregroundStyle(Color.velix.ink2)
                    Text(minutes).velixType(.ridingBigNumber).foregroundStyle(Color.velix.ink)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(station).velixType(VelixType.ridingStreet.sized(22, lineHeight: 24)).foregroundStyle(Color.velix.ink)
                    Text(arrival).velixType(VelixType.body.sized(14, lineHeight: 18)).foregroundStyle(Color.velix.ink2)
                }
            }
            HStack(spacing: CGFloat.velix.xs) {
                VelixIconView(.train, size: 20)
                Text("Next stop **\(nextStop)** · then \(thenStop)").velixType(VelixType.body.sized(15, lineHeight: 20))
            }
            .foregroundStyle(Color.velix.ink)
            .padding(.top, CGFloat.velix.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) { Rectangle().fill(Color.velix.line).frame(height: 1) }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 3) {
                    ForEach(Array(bikeCarriages.enumerated()), id: \.offset) { i, bikes in
                        UnevenRoundedRectangle(topLeadingRadius: i == 0 ? 12 : 4, bottomLeadingRadius: 4, bottomTrailingRadius: 4, topTrailingRadius: 4)
                            .fill(bikes ? Color.velix.ink : Color.velix.surface2)
                            .frame(height: 26)
                            .overlay { if bikes { VelixIconView(.bike, size: 16).foregroundStyle(Color.velix.surface) } }
                    }
                    VelixIconView(.arrowLeft, size: 18).foregroundStyle(Color.velix.ink).padding(.leading, 4)
                }
                .accessibilityHidden(true)
                Text(note).velixType(VelixType.body.sized(14, lineHeight: 18)).foregroundStyle(Color.velix.ink2)
            }
        }
        .padding(CGFloat.velix.m)
        .background(Color.velix.surface, in: RoundedRectangle(cornerRadius: 24))
        .velixElevation(VelixElevations.e1, in: RoundedRectangle(cornerRadius: 24))
        .accessibilityElement(children: .combine)
    }
}

extension TransitCard.Model {
    /// P2 sample (Milan → Monza).
    static let sample = TransitCard.Model(
        title: "Bike + train", subtitle: "5.5 km by bike · arrive 09:26", minutes: 52,
        segments: [.init(kind: .ride, minutes: 9, label: "Ride 9"), .init(kind: .wait, minutes: 6, label: "Wait 6"),
                   .init(kind: .train, minutes: 16, label: "Train 16"), .init(kind: .ride, minutes: 14, label: "Ride 14")],
        departures: ["08:12", "08:27", "08:42"],
        legs: [.init(mode: .ride, title: "Ride 9 min to Milano Centrale", detail: "2.1 km · bike parking at Piazza Duca d’Aosta"),
               .init(mode: .train, title: "Train 08:12 → Monza 08:28", detail: "Regional · bike allowed · platform on arrival"),
               .init(mode: .ride, title: "Ride 14 min to Villa Reale", detail: "3.4 km")],
        ticketsLabel: "Tickets on Trenord")
}

#Preview {
    ScrollView {
        VStack(spacing: 16) {
            TransitSuggestionRow(mode: .train, title: "Bike + train · 52 min", subtitle: "26 min faster than Best")
            TransitSuggestionRow(mode: .metro(.m1), title: "Bike + M1 · 31 min", subtitle: "12 min faster than Best")
            TransitCard(model: .sample, selectedDeparture: .constant(0))
            OnTrainCard(minutes: "6 min", station: "Monza", arrival: "08:28", nextStop: "Sesto S. Giovanni", thenStop: "Monza",
                        bikeCarriages: [true, true, false, false, false, false], note: "Bike space in the first 2 carriages · exit on the right")
        }
        .padding()
    }
    .background(Color.velix.canvas)
}
