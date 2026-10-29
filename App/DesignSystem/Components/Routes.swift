import SwiftUI

/// RouteKeyTile (P7 S7): the route's number, as on the map. Accent with casing in focus, surface ringed in ink otherwise.
struct RouteKeyTile: View {
    let number: Int
    var focused = false

    var body: some View {
        Text("\(number)").velixType(VelixType.label.sized(15, lineHeight: 18)).monospacedDigit()
            .foregroundStyle(focused ? Color.velix.accentInk : Color.velix.ink)
            .frame(width: 28, height: 28)
            .background(focused ? Color.velix.accent : Color.velix.surface, in: RoundedRectangle(cornerRadius: 8))
            .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(focused ? Color.velix.casing : Color.velix.ink, lineWidth: 2) }
            .accessibilityLabel("Route \(number)")
    }
}

/// EVBadge (P7): "EV 5", navy with a khaki ring and the bike.
struct EVBadge: View {
    let number: Int

    var body: some View {
        HStack(spacing: 4) {
            VelixIconView(.bike, size: 14)
            Text("EV \(number)").velixType(VelixType.label.sized(12, lineHeight: 14))
        }
        .foregroundStyle(Color.velix.palettePaper)
        .padding(.leading, 5).padding(.trailing, 7).frame(height: 24)
        .background(Color.velix.paletteNavy, in: RoundedRectangle(cornerRadius: 6))
        .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(Color.velix.paletteKhaki, lineWidth: 1.5) }
        .fixedSize()
        .accessibilityLabel("EuroVelo \(number)")
    }
}

/// NetworkChip (P7): "Regional", "Local", "MTB".
struct NetworkChip: View {
    let text: String

    var body: some View {
        Text(text).velixType(VelixType.label.sized(12, lineHeight: 14)).foregroundStyle(Color.velix.ink2)
            .padding(.horizontal, 8).frame(height: 24)
            .background(Color.velix.surface2, in: RoundedRectangle(cornerRadius: 6))
            .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(Color.velix.line, lineWidth: 1) }
            .fixedSize()
    }
}

/// What a route card and the selected sheet show (P7 S7a–S7c), from a ``CycleRoute`` or a sample.
struct RouteSummary: Hashable {
    var key: Int
    var name: String
    var km: String
    var eurovelo: Int?
    var network: String
    var note: String
    /// Car-free paved, quiet road, gravel (and busier road), shares.
    var mix: [MixCategory: Double]
    var description = ""
    var climb = ""
    var time = ""
    var rideType: RideType = .city
}

extension RouteSummary {
    /// The S7 mix bar's keys: car-free paved = protected, quiet road = quiet, gravel = unpaved, the rest mixed traffic.
    static func mix(_ m: CycleRoute.Mix?, paved: Double) -> [MixCategory: Double] {
        guard let m else { return [.protected: paved, .unpaved: 1 - paved] }
        return [.protected: m.carFree, .quiet: m.quiet, .unpaved: m.unpaved, .mixed: m.road]
    }
}

/// RouteListCard (P7 S7a): key tile, name and km, the EuroVelo badge or network chip with a note, the mix bar.
/// In focus: ringed in ink, raised.
struct RouteListCard: View {
    let route: RouteSummary
    var focused = false
    var onTap: () -> Void = {}

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                RouteKeyTile(number: route.key, focused: focused)
                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(route.name).velixType(VelixType.cardTitle.sized(17, lineHeight: 20)).lineLimit(1)
                        Spacer(minLength: 0)
                        Text(route.km).velixType(VelixType.cardTitle.sized(17, lineHeight: 20)).monospacedDigit().fixedSize()
                    }
                    HStack(spacing: 8) {
                        badge
                        Text(route.note).velixType(VelixType.body.sized(14, lineHeight: 18)).foregroundStyle(Color.velix.ink2).lineLimit(1)
                    }
                    ComfortMixBar(mix: route.mix, size: .compact)
                }
            }
            .foregroundStyle(Color.velix.ink)
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(Color.velix.surface, in: RoundedRectangle(cornerRadius: CGFloat.velix.radius.card))
            .overlay(RoundedRectangle(cornerRadius: CGFloat.velix.radius.card)
                .strokeBorder(focused ? Color.velix.ink : Color.velix.line, lineWidth: focused ? 2 : 1))
            .velixElevation(focused ? VelixElevations.e2 : VelixElevations.e0)
            .contentShape(Rectangle())
        }
        .buttonStyle(VelixPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(focused ? .isSelected : [])
    }

    @ViewBuilder private var badge: some View {
        if let ev = route.eurovelo { EVBadge(number: ev) } else { NetworkChip(text: route.network) }
    }
}

/// RouteDetail (P7 S7c): the selected route: key, title, badges, close; description; km, climb, time by type; the
/// mix bar with its legend; Ride this route.
struct RouteDetail: View {
    let route: RouteSummary
    var onClose: () -> Void = {}
    var onRide: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                RouteKeyTile(number: route.key, focused: true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(route.name).velixType(VelixType.title1.sized(24, lineHeight: 28)).accessibilityAddTraits(.isHeader)
                    HStack(spacing: 8) {
                        if let ev = route.eurovelo { EVBadge(number: ev) }
                        NetworkChip(text: route.network)
                    }
                }
                Spacer(minLength: 0)
                Button(action: onClose) {
                    VelixIconView(.x, size: 18).foregroundStyle(Color.velix.ink)
                        .frame(width: 36, height: 36).background(Color.velix.surface2, in: Circle())
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(VelixPressStyle())
                .accessibilityLabel("Close")
            }
            if !route.description.isEmpty {
                Text(route.description).velixType(VelixType.body.sized(15, lineHeight: 22)).foregroundStyle(Color.velix.ink2)
                    .lineLimit(3).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 22) {
                stat(route.km.replacingOccurrences(of: " km", with: ""), "km")
                if !route.climb.isEmpty { stat(route.climb, "m climb") }
                stat(route.time, "by \(route.rideType.name)")
            }
            VStack(alignment: .leading, spacing: 8) {
                ComfortMixBar(mix: route.mix, size: .large)
                RouteMixLegend()
            }
            PrimaryButton(title: "Ride this route", icon: .navigation, action: onRide)
        }
        .foregroundStyle(Color.velix.ink)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).velixType(VelixType.numberL.sized(26, lineHeight: 26)).monospacedDigit().lineLimit(1).fixedSize()
            Text(label).velixType(VelixType.body.sized(13, lineHeight: 16)).foregroundStyle(Color.velix.ink3)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The S7 legend: car-free paved, quiet road, gravel.
struct RouteMixLegend: View {
    var body: some View {
        HStack(spacing: 14) {
            item(.protected, "Car-free paved")
            item(.quiet, "Quiet road")
            item(.unpaved, "Gravel")
        }
    }

    private func item(_ c: MixCategory, _ label: String) -> some View {
        HStack(spacing: 6) {
            MixSwatch(category: c).frame(width: 14, height: 10).clipShape(RoundedRectangle(cornerRadius: 3))
            Text(label).velixType(VelixType.body.sized(13, lineHeight: 16)).foregroundStyle(Color.velix.ink2)
        }
    }
}

extension RouteSummary {
    /// P7 sample routes (design/tools/p7gen.js `RT`).
    static let samples: [RouteSummary] = [
        .init(key: 1, name: "Alzaia Naviglio Pavese", km: "33 km", eurovelo: 5, network: "Regional", note: "Flat towpath along the canal to Pavia",
              mix: [.protected: 0.62, .quiet: 0.08, .unpaved: 0.30],
              description: "Flat towpath from the Darsena to Pavia, on EuroVelo 5. Mostly car-free; the last third is packed gravel.",
              climb: "+40", time: "2 h 05", rideType: .gravel),
        .init(key: 2, name: "Naviglio Martesana", km: "38 km", network: "Regional", note: "Canal path east to Cassano d’Adda",
              mix: [.protected: 0.85, .quiet: 0.10, .unpaved: 0.05], climb: "+60", time: "2 h 15", rideType: .gravel),
        .init(key: 3, name: "Groane MTB trails", km: "14 km", network: "MTB", note: "Heath and woods, short steep pitches",
              mix: [.unpaved: 0.70, .quiet: 0.10, .protected: 0.20], climb: "+120", time: "1 h 05", rideType: .gravel),
        .init(key: 3, name: "Parco Nord loop", km: "9 km", network: "Local", note: "Paved park loop, no cars",
              mix: [.protected: 1], climb: "+15", time: "35 min", rideType: .gravel),
    ]
}
