import SwiftUI

/// You → See all rides: every ride, newest first, by month. A ride opens its S6 summary; swipe to delete it.
struct RideHistoryView: View {
    let history: RideHistory
    /// Today for "Today" / "Yesterday" (snapshots pin it).
    var now: Date?
    var onOpen: (RideRecord) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(Self.months(history.rides), id: \.title) { month in
                    Section(month.title) {
                        ForEach(month.rides) { ride in
                            RideRow(destination: ride.destination, detail: ride.detail(now: now ?? AppClock.now), glyph: ride.type.glyph,
                                    transit: ride.transit != nil, value: Format.km(ride.meters), divider: false) { onOpen(ride) }
                                .listRowBackground(Color.velix.surface)
                                .swipeActions {
                                    Button("Delete", role: .destructive) { history.delete(ride) }
                                }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.velix.canvas)
            .tint(Color.velix.ink)
            .overlay {
                if history.rides.isEmpty {
                    Text("Your rides show up here when they end.").velixType(.body).foregroundStyle(Color.velix.ink2)
                }
            }
            .navigationTitle("Your rides")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
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
