import SwiftUI

/// You → See all rides: every ride, newest first, by month. A ride opens its S6 summary; touch and hold to delete it.
struct RideHistoryView: View {
    let history: RideHistory
    /// Today for "Today" / "Yesterday" (snapshots pin it).
    var now: Date?
    var onOpen: (RideRecord) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Your rides").velixType(.title2).accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Done") { dismiss() }.velixType(.label).frame(minWidth: 44, minHeight: 44)
            }
            .foregroundStyle(Color.velix.ink)
            .padding(.horizontal, CGFloat.velix.m).padding(.top, CGFloat.velix.s)
            // The app's own grouped rows, not a List or a navigation bar (they look different from one iOS to the next).
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(Self.months(history.rides), id: \.title) { month in
                        VStack(alignment: .leading, spacing: 6) {
                            SectionLabel(month.title)
                            VStack(spacing: 0) {
                                ForEach(Array(month.rides.enumerated()), id: \.element.id) { i, ride in
                                    RideRow(destination: ride.destination, detail: ride.detail(now: now ?? AppClock.now), glyph: ride.type.glyph,
                                            transit: ride.transit != nil, value: Format.km(ride.meters), divider: i > 0) { onOpen(ride) }
                                        .contextMenu {
                                            Button("Delete ride", role: .destructive) { history.delete(ride) }
                                        }
                                }
                            }
                            .padding(.horizontal, CGFloat.velix.m)
                            .background(Color.velix.surface, in: RoundedRectangle(cornerRadius: CGFloat.velix.radius.card))
                        }
                    }
                    if !history.rides.isEmpty {
                        Text("Touch and hold a ride to delete it.").velixType(.footnote).foregroundStyle(Color.velix.ink3).padding(.horizontal, 4)
                    }
                }
                .padding(CGFloat.velix.m)
            }
            .background(Color.velix.canvas)
            .overlay {
                if history.rides.isEmpty {
                    Text("Your rides show up here when they end.").velixType(.body).foregroundStyle(Color.velix.ink2)
                }
            }
        }
        .background(Color.velix.canvas)
    }

    /// "October 2026" sections, newest first (the rides come sorted).
    static func months(_ rides: [RideRecord]) -> [(title: String, rides: [RideRecord])] {
        var out: [(title: String, rides: [RideRecord])] = []
        let style = Date.FormatStyle(locale: Locale(identifier: "en_GB")).month(.wide).year()
        for ride in rides {
            let title = ride.started.formatted(style)
            if out.last?.title == title { out[out.count - 1].rides.append(ride) } else { out.append((title, [ride])) }
        }
        return out
    }
}
