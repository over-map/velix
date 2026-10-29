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

    /// A badge in a metro colour family (P3 mapRules).
    static func family(_ family: String, name: String) -> MetroBadge {
        switch family {
        case "red": MetroBadge(name: name, color: Color.velix.transitMetroRed, ink: Color.velix.transitMetroRedInk)
        case "orange": MetroBadge(name: name, color: Color.velix.transitMetroOrange, ink: Color.velix.transitMetroOrangeInk)
        case "yellow": MetroBadge(name: name, color: Color.velix.transitMetroYellow, ink: Color.velix.transitMetroYellowInk)
        case "olive": MetroBadge(name: name, color: Color.velix.transitMetroOlive, ink: Color.velix.transitMetroOliveInk)
        case "green": MetroBadge(name: name, color: Color.velix.transitMetroGreen, ink: Color.velix.transitMetroGreenInk)
        case "cyan": MetroBadge(name: name, color: Color.velix.transitMetroCyan, ink: Color.velix.transitMetroCyanInk)
        case "lightblue": MetroBadge(name: name, color: Color.velix.transitMetroLightblue, ink: Color.velix.transitMetroLightblueInk)
        case "blue": MetroBadge(name: name, color: Color.velix.transitMetroBlue, ink: Color.velix.transitMetroBlueInk)
        case "purple": MetroBadge(name: name, color: Color.velix.transitMetroPurple, ink: Color.velix.transitMetroPurpleInk)
        case "pink": MetroBadge(name: name, color: Color.velix.transitMetroPink, ink: Color.velix.transitMetroPinkInk)
        case "brown": MetroBadge(name: name, color: Color.velix.transitMetroBrown, ink: Color.velix.transitMetroBrownInk)
        default: MetroBadge(name: name, color: Color.velix.transitMetroGrey, ink: Color.velix.transitMetroGreyInk)
        }
    }
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

/// TransitSuggestionRow (P4 S3d): one row under the bike routes, outlined in train slate. The subtitle leads with the
/// saving in bold ("**21 min faster** · ride to Centrale, train to Monza, ride into the park").
struct TransitSuggestionRow: View {
    let mode: TransitMode
    let title: String
    /// Markdown: the bold lead.
    let subtitle: String
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                TransitModeTile(mode: mode)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).velixType(VelixType.rowTitle.sized(16, lineHeight: 20)).foregroundStyle(Color.velix.ink)
                    Text((try? AttributedString(markdown: subtitle)) ?? AttributedString(subtitle))
                        .velixType(VelixType.rowSubtitle.sized(14, lineHeight: 19)).foregroundStyle(Color.velix.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VelixIconView(.chevronRight, size: 20).foregroundStyle(Color.velix.ink)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
        }
        .buttonStyle(SurfaceRowStyle(outline: Color.velix.transitTrain, outlineWidth: 1.5, cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// "Bike only · **52 min** Best · 45 min Fastest" (P4 S3e): the bike routes, folded while bike + transit is chosen.
struct BikeOnlyRow: View {
    /// Markdown: the bold Best time.
    let text: String
    var action: () -> Void = {}
    var body: some View {
        Button(action: action) {
            HStack {
                Text((try? AttributedString(markdown: text)) ?? AttributedString(text))
                    .velixType(VelixType.body.sized(14, lineHeight: 18)).foregroundStyle(Color.velix.ink2)
                Spacer(minLength: 0)
                VelixIconView(.chevronDown, size: 18).foregroundStyle(Color.velix.ink)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.velix.line, lineWidth: 1))
        }
        .buttonStyle(VelixPressStyle())
        .accessibilityHint("Shows the bike routes")
    }
}

/// Bordered surface row that turns surface-2 while pressed (P2 "Pressed").
struct SurfaceRowStyle: ButtonStyle {
    var pressed = false
    var outline = Color.velix.line
    var outlineWidth: CGFloat = 1
    var cornerRadius = CGFloat.velix.radius.card
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed || pressed ? Color.velix.surface2 : Color.velix.surface,
                        in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(outline, lineWidth: outlineWidth))
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

/// TransitCard (P4 S3e): the bike + transit option. Trip bar, next trains, the run and what to do, one ticket link.
struct TransitCard: View {
    struct Model {
        var title: String
        var subtitle: String
        var minutes: Int
        var segments: [TripBar.Segment]
        /// "08:16", "08:46", "09:16"
        var departures: [String]
        /// "Trenord R 10834 · 08:16 → Monza 08:27"
        var train: String
        /// "Ride 7 min to Centrale · platform planned: check the board · bikes allowed · ride 6 min into the park"
        var detail: String
        var ticketsLabel: String?
        var footnote: String?
    }
    let model: Model
    @Binding var selectedDeparture: Int
    var onTickets: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.title).velixType(.cardTitle).foregroundStyle(Color.velix.ink)
                    Text(model.subtitle).velixType(VelixType.body.sized(13, lineHeight: 17)).foregroundStyle(Color.velix.ink3)
                }
                Spacer(minLength: CGFloat.velix.xs)
                Text("\(model.minutes) min").velixType(VelixType.numberL.sized(30, lineHeight: 30)).foregroundStyle(Color.velix.ink)
            }
            .accessibilityElement(children: .combine)
            TripBar(segments: model.segments)
            HStack(spacing: 8) {
                SectionLabel("Next trains")
                ForEach(Array(model.departures.enumerated()), id: \.offset) { i, time in
                    Button { selectedDeparture = i } label: {
                        Text(time).velixType(.label).monospacedDigit()
                            .foregroundStyle(i == selectedDeparture ? Color.velix.surface : Color.velix.ink)
                            .padding(.horizontal, CGFloat.velix.s).frame(height: 36)
                            .background(i == selectedDeparture ? Color.velix.ink : Color.velix.surface2,
                                        in: RoundedRectangle(cornerRadius: 8))
                            .frame(minHeight: CGFloat.velix.touch.min)
                    }
                    .buttonStyle(VelixPressStyle())
                    .accessibilityLabel("Train at \(time)")
                    .accessibilityAddTraits(i == selectedDeparture ? .isSelected : [])
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(model.train).velixType(VelixType.rowTitle.sized(15, lineHeight: 20)).foregroundStyle(Color.velix.ink)
                Text(model.detail).velixType(VelixType.body.sized(14, lineHeight: 19)).foregroundStyle(Color.velix.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            HStack {
                if let tickets = model.ticketsLabel {
                    Button(action: onTickets) {
                        HStack(spacing: 6) {
                            Text(tickets).underline()
                            VelixIconView(.externalLink, size: 16)
                        }
                        .velixType(VelixType.label.sized(15, lineHeight: 19)).foregroundStyle(Color.velix.ink)
                        .frame(minHeight: CGFloat.velix.touch.min)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(.isLink)
                }
                Spacer(minLength: 0)
                if let footnote = model.footnote {
                    Text(footnote).velixType(VelixType.body.sized(12, lineHeight: 15)).foregroundStyle(Color.velix.ink3)
                }
            }
        }
        .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 4)
        .background(Color.velix.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.velix.ink, lineWidth: 2))
        .velixElevation(VelixElevations.e2)
    }
}

/// OnTrainCard (P6 S5d): the bottom sheet on the train. One big number (minutes to the stop), the stops, where the
/// bikes go, the buzz before the stop and the final arrival.
struct OnTrainCard: View, Equatable {
    struct Stop: Hashable {
        enum State: Hashable { case departed, next, end }
        var name: String
        var time: String
        var state: State
    }
    /// "Trenord R 10834 to Monza"
    var train: String
    /// "Get off at Monza"
    var getOff: String
    /// "1 stop before yours"
    var stopsLeft: String
    var minutes: Int
    var stops: [Stop]
    /// Carriages from the front, true where bikes go (nil: the operator doesn't say which).
    var carriages: [Bool]?
    /// "Bike carriage at the front", "Carriage with the bike area"
    var carriageNote: String
    /// "Villa Reale 08:36"
    var arrival: String
    var metro = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            countdown
            timeline
            bikes.padding(.top, 12).overlay(alignment: .top) { divider }
            footer.padding(.top, 12).overlay(alignment: .top) { divider }
        }
        .padding(EdgeInsets(top: 18, leading: 18, bottom: 34, trailing: 18))
        .background(Color.velix.surface, in: UnevenRoundedRectangle(topLeadingRadius: 26, topTrailingRadius: 26))
        .velixElevation(VelixElevations.e3, in: UnevenRoundedRectangle(topLeadingRadius: 26, topTrailingRadius: 26))
    }

    private var divider: some View { Rectangle().fill(Color.velix.line).frame(height: 1) }

    private var header: some View {
        HStack(spacing: 8) {
            if metro { VelixIconView(VelixGlyph.metro, size: 18) } else { VelixIconView(VelixIcon.trainFront, size: 18) }
            Text(train).lineLimit(1)
        }
        .velixType(VelixType.label.sized(14, lineHeight: 18))
        .foregroundStyle(Color.velix.ink2)
    }

    private var countdown: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(getOff).velixType(VelixType.ridingStreet.sized(26, lineHeight: 29)).foregroundStyle(Color.velix.ink)
                Text(stopsLeft).velixType(VelixType.body.sized(15, lineHeight: 19)).foregroundStyle(Color.velix.ink2)
            }
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("in").velixType(VelixType.ridingLabel.sized(15, lineHeight: 18)).foregroundStyle(Color.velix.ink2)
                Text("\(minutes)").velixType(VelixType.ridingBigNumber.sized(64, lineHeight: 58))
                Text("min").velixType(VelixType.ridingStreet.sized(24, lineHeight: 26))
            }
            .foregroundStyle(Color.velix.ink)
            .accessibilityElement(children: .combine)
        }
    }

    private var timeline: some View {
        VStack(spacing: 0) {
            ForEach(Array(stops.enumerated()), id: \.offset) { i, stop in
                stopRow(stop, first: i == 0, last: i == stops.count - 1)
            }
        }
    }

    private func stopRow(_ stop: Stop, first: Bool, last: Bool) -> some View {
        let departed = stop.state == .departed
        let type = stop.state == .end ? VelixType.rowTitle.sized(17, lineHeight: 21) : VelixType.body.sized(16, lineHeight: 20)
        return HStack(spacing: 12) {
            StopDot(state: stop.state, first: first, last: last).frame(width: 20)
            Text(stop.name + (departed ? " · departed" : "")).velixType(type)
                .foregroundStyle(departed ? Color.velix.ink3 : Color.velix.ink)
            Spacer(minLength: 0)
            Text(stop.time).velixType(VelixType.label.sized(15, lineHeight: 19)).monospacedDigit()
                .foregroundStyle(departed ? Color.velix.ink3 : Color.velix.ink2)
        }
        .frame(minHeight: 34)
        .accessibilityElement(children: .combine)
    }

    private var bikes: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let carriages {
                HStack(spacing: 3) {
                    VelixIconView(.arrowLeft, size: 18).foregroundStyle(Color.velix.ink3)
                    ForEach(Array(carriages.enumerated()), id: \.offset) { i, bikes in Carriage(front: i == 0, bikes: bikes) }
                }
                .accessibilityHidden(true)
            }
            Text(carriageNote).velixType(VelixType.rowTitle.sized(16, lineHeight: 20)).foregroundStyle(Color.velix.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                VelixIconView(.vibrate, size: 20)
                Text("Velix buzzes 2 min before")
            }
            .velixType(VelixType.body.sized(15, lineHeight: 19))
            .foregroundStyle(Color.velix.ink2)
            Spacer(minLength: 0)
            Text(arrival).velixType(VelixType.label.sized(15, lineHeight: 19)).foregroundStyle(Color.velix.ink).lineLimit(1)
        }
    }

    /// One carriage, the front one rounded: accent with the casing and a bike where bikes go.
    private struct Carriage: View {
        let front: Bool
        let bikes: Bool
        var body: some View {
            let shape = UnevenRoundedRectangle(topLeadingRadius: front ? 12 : 5, bottomLeadingRadius: front ? 12 : 5,
                                               bottomTrailingRadius: 5, topTrailingRadius: 5)
            shape.fill(bikes ? Color.velix.accent : Color.velix.surface2)
                .overlay {
                    if bikes {
                        shape.strokeBorder(Color.velix.casing, lineWidth: 1.5)
                        VelixIconView(.bike, size: 18).foregroundStyle(Color.velix.accentInk)
                    }
                }
                .frame(height: 30)
        }
    }

    /// The timeline dot and rail (train slate): departed filled, next ringed, the stop in accent with casing.
    private struct StopDot: View {
        let state: Stop.State
        let first: Bool
        let last: Bool
        var body: some View {
            ZStack {
                VStack(spacing: 0) {
                    Rectangle().fill(first ? Color.clear : Color.velix.transitTrain).frame(width: 2, height: 17)
                    Rectangle().fill(last ? Color.clear : Color.velix.transitTrain).frame(width: 2, height: 17)
                }
                switch state {
                case .departed: Circle().fill(Color.velix.transitTrain).frame(width: 10, height: 10)
                case .next: Circle().fill(Color.velix.surface).overlay(Circle().strokeBorder(Color.velix.transitTrain, lineWidth: 2))
                        .frame(width: 10, height: 10)
                case .end: Circle().fill(Color.velix.accent).overlay(Circle().stroke(Color.velix.casing, lineWidth: 2)).frame(width: 14, height: 14)
                }
            }
        }
    }
}

/// Late / missed (P6 S5b, S5c): takes the hazard card's place for 8 s, in the warning colours.
struct TransitNotice: View {
    enum Kind: Hashable { case late, missed }
    let kind: Kind
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VelixIconView(kind == .late ? .timer : .trainFront, size: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).velixType(VelixType.ridingStreet.sized(20, lineHeight: 24))
                Text(message).velixType(VelixType.body.sized(16, lineHeight: 22)).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(Color.velix.warningInk)
        .padding(EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 16))
        .background(Color.velix.warningSurface, in: RoundedRectangle(cornerRadius: 20))
        .velixElevation(VelixElevations.e2, in: RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

extension OnTrainCard {
    /// P6 S5d sample.
    static let sample = OnTrainCard(train: "Trenord R 10834 to Monza", getOff: "Get off at Monza", stopsLeft: "1 stop before yours",
                                    minutes: 6,
                                    stops: [.init(name: "Milano Centrale", time: "08:16", state: .departed),
                                            .init(name: "Sesto San Giovanni", time: "08:23", state: .next),
                                            .init(name: "Monza", time: "08:27", state: .end)],
                                    carriages: [true, false, false, false, false], carriageNote: "Bike carriage at the front",
                                    arrival: "Villa Reale 08:36")
}

extension TransitCard.Model {
    /// P4 S3e sample (Porta Venezia → Villa Reale, Monza; P4's illustrative timetable).
    static let sample = TransitCard.Model(
        title: "Bike + train", subtitle: "13 min by bike · arrive 08:36", minutes: 31,
        segments: [.init(kind: .ride, minutes: 7, label: "Ride 7"), .init(kind: .train, minutes: 11, label: "Train 11"),
                   .init(kind: .ride, minutes: 6, label: "Ride 6")],
        departures: ["08:16", "08:46", "09:16"],
        train: "Trenord R 10834 · 08:16 → Monza 08:27",
        detail: "Ride 7 min to Centrale · platform planned: check the board · bikes allowed · ride 6 min into the park",
        ticketsLabel: "Ticket · Trenitalia app", footnote: TransitCopy.footnote)
}

#Preview {
    ScrollView {
        VStack(spacing: 16) {
            TransitSuggestionRow(mode: .train, title: "Long ride? Hop on the train with your bike",
                                 subtitle: "**21 min faster** · ride to Centrale, train to Monza, ride into the park")
            BikeOnlyRow(text: "Bike only · **52 min** Best · 45 min Fastest")
            TransitCard(model: .sample, selectedDeparture: .constant(0))
            OnTrainCard.sample
            TransitNotice(kind: .late, title: "Running late", message: "Switched to the fastest route to catch the 08:16. It adds 120 m of cobbles.")
        }
        .padding()
    }
    .background(Color.velix.canvas)
}
