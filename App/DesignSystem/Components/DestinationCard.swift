import SwiftUI

/// The tile in front of a place (S2 rows, the destination card): its kind, or its metro lines.
struct PlaceKindTile: View {
    let place: Place

    var body: some View {
        switch place.kind {
        case .metro where !place.lines.isEmpty:
            HStack(spacing: 2) {
                ForEach(Array(place.lines.prefix(2).enumerated()), id: \.offset) { i, ref in
                    MetroBadge.family(place.lineFamilies.indices.contains(i) ? place.lineFamilies[i] : "grey", name: ref)
                }
            }
        default:
            icon.foregroundStyle(Color.velix.ink).frame(width: 40, height: 40)
                .background(Color.velix.surface2, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    @ViewBuilder private var icon: some View {
        switch place.kind {
        case .station: VelixIconView(.train, size: 22)
        case .metro: VelixIconView(.metro, size: 22)
        case .park: VelixIconView(.trees, size: 22)
        default: VelixIconView(.mapPin, size: 22)
        }
    }
}

/// The destination card (search first, Filippo 2 Nov): the picked place framed on the map, then Find route. In a
/// region not on the phone, Find route asks to download it; outside every region on offer, it says so.
struct DestinationCard: View {
    enum Availability: Equatable {
        /// Routes work: Find route.
        case routable
        /// In a region on offer that isn't on the phone: Find route asks to download it first.
        case needsDownload(region: String, megabytes: Int64)
        /// That region downloading now.
        case downloading(region: String, fraction: Double)
        /// Outside every region Velix offers.
        case notCovered
    }

    let place: Place
    /// "1.2 km" from the rider, when the rider's position is known.
    var distance: String?
    var availability: Availability = .routable
    var onFindRoute: () -> Void = {}
    var onClose: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: CGFloat.velix.s) {
            HStack(alignment: .top, spacing: CGFloat.velix.s) {
                PlaceKindTile(place: place)
                VStack(alignment: .leading, spacing: 2) {
                    Text(place.name).velixType(VelixType.title2.sized(22, lineHeight: 26)).foregroundStyle(Color.velix.ink)
                        .lineLimit(2).accessibilityAddTraits(.isHeader)
                    Text(detail).velixType(.rowSubtitle).foregroundStyle(Color.velix.ink2).lineLimit(2)
                }
                Spacer(minLength: 0)
                SheetCloseButton(action: onClose)
            }
            switch availability {
            case .routable, .needsDownload:
                PrimaryButton(title: "Find route", icon: .route, casing: true, action: onFindRoute)
            case let .downloading(region, fraction):
                VStack(alignment: .leading, spacing: CGFloat.velix.xs) {
                    HStack {
                        Text("Downloading \(region)").velixType(.label)
                        Spacer()
                        Text("\(Int((fraction * 100).rounded())) %").velixType(.label).monospacedDigit().foregroundStyle(Color.velix.ink2)
                    }
                    ProgressBar(fraction: fraction)
                    Text("The route opens when the map is on the phone.").velixType(.footnote).foregroundStyle(Color.velix.ink2)
                }
                .foregroundStyle(Color.velix.ink)
                .accessibilityElement(children: .combine)
            case .notCovered:
                HStack(alignment: .top, spacing: CGFloat.velix.xs) {
                    VelixIconView(.mapPinOff, size: 20)
                    Text("Velix covers Lombardy and its neighbours for now. You can still look at the map here.")
                        .velixType(VelixType.body.sized(14, lineHeight: 19))
                }
                .foregroundStyle(Color.velix.ink)
                .padding(CGFloat.velix.s)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.velix.surface2, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(EdgeInsets(top: CGFloat.velix.m, leading: CGFloat.velix.m, bottom: 34, trailing: CGFloat.velix.m))
        .background(Color.velix.surface, in: UnevenRoundedRectangle(topLeadingRadius: CGFloat.velix.radius.sheet,
                                                                   topTrailingRadius: CGFloat.velix.radius.sheet))
        .velixElevation(VelixElevations.e3, in: RoundedRectangle(cornerRadius: CGFloat.velix.radius.sheet))
    }

    private var detail: String {
        [place.subtitle.isEmpty ? nil : place.subtitle, distance].compactMap { $0 }.joined(separator: " · ")
    }
}
