import SwiftUI

/// What S6 shows about a finished ride (P7), taken from the session when it ends at the door.
struct RideSummaryModel: Identifiable, Equatable {
    let id = UUID()
    var arrived: Date
    var place: String
    var rideType: RideType
    var option: String
    var meters: Double
    var movingSeconds: TimeInterval
    var climb: Double
    /// The ride as ridden (the planned route when GPS gave too little).
    var track: [LatLon]
    var gpx: URL?

    var km: String { String(format: "%.1f", meters / 1000) }
    var minutes: String { "\(max(1, Int((movingSeconds / 60).rounded())))" }
    var climbText: String { "\(Int(climb.rounded()))" }
    var arrivedText: String { arrived.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)) }
}

extension RideSummaryModel {
    @MainActor
    init(_ session: RideSession, at now: Date = AppClock.now) {
        let stats = session.stats
        let ridden = session.log?.ridden ?? []
        self.init(arrived: now, place: session.destination.name, rideType: session.rules.rideType,
                  option: session.choice == .best ? session.rules.rideType.bestName : "Fastest",
                  meters: stats.meters, movingSeconds: stats.movingSeconds, climb: stats.climb,
                  track: ridden.count > 1 ? ridden : session.option.analysis.shape, gpx: session.gpx)
    }
}

extension RideSummaryModel {
    /// A past ride from the history (You → Your rides).
    init(_ record: RideRecord) {
        self.init(arrived: record.ended, place: record.destination, rideType: record.type,
                  option: record.option,
                  meters: record.meters, movingSeconds: record.movingSeconds, climb: record.climb,
                  track: record.track, gpx: record.gpxURL.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil })
    }
}

/// S6 Ride summary (P7): the ride on the map, the summary sheet over it. Shown once, after the ride ends by itself.
/// S6a when Apple Health is on (the ride is saved there), S6b with Connect otherwise; S6c is built and snapshot-tested.
/// Also opens for a past ride (You → Your rides).
struct RideSummaryView: View {
    let model: RideSummaryModel
    var connections: RideSummary.Connections = .notConnected
    var issue: RideSummary.Issue?
    var mapStyle: MapStyleKind = .standard
    var onConnect: () -> Void = {}
    var onDone: () -> Void = {}

    @Environment(\.colorScheme) private var scheme
    @Environment(\.mapAppearance) private var mapAppearance
    @Environment(\.liveMap) private var liveMap
    @State private var sheetHeight: CGFloat = 450

    var body: some View {
        ZStack(alignment: .bottom) {
            map.ignoresSafeArea()
            VStack(spacing: 16) {
                Capsule().fill(Color.velix.line).frame(width: 36, height: 5).frame(maxWidth: .infinity)
                RideSummary(arrived: model.arrivedText, place: model.place, rideType: model.rideType, option: model.option,
                            km: model.km, minutes: model.minutes, climb: model.climbText, connections: connections,
                            issue: issue, gpx: model.gpx, onConnect: onConnect, onDone: onDone)
            }
            .padding(EdgeInsets(top: 8, leading: 16, bottom: 34, trailing: 16))
            .background(Color.velix.surface, in: UnevenRoundedRectangle(topLeadingRadius: CGFloat.velix.radius.sheet,
                                                                       topTrailingRadius: CGFloat.velix.radius.sheet))
            .velixElevation(VelixElevations.e3, in: RoundedRectangle(cornerRadius: CGFloat.velix.radius.sheet))
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { sheetHeight = VelixMap.covered(fromTop: $0) }
            .ignoresSafeArea(edges: .bottom)
        }
    }

    @ViewBuilder private var map: some View {
        if liveMap {
            VelixMap(style: mapStyle, mode: MapMode(scheme, mapAppearance), route: MapRouteModel(best: model.track, endName: model.place),
                     camera: MapCamera(center: model.track.last ?? RideView.milan, zoom: 14),
                     insets: UIEdgeInsets(top: 60, left: 0, bottom: sheetHeight, right: 0),
                     fit: model.track.count > 1 ? model.track : nil)
        } else {
            Color.velix.surface2
        }
    }
}
