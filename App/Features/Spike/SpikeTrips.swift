#if DEBUG
import CoreLocation

/// Fixed Milan trips for the M1 benchmark (BUILD_PLAN M1: Porta Venezia → Politecnico,
/// plus longer ones to check the < 1.5 s for 5 km target).
struct SpikeTrip: Identifiable, Hashable {
    let id: String
    let from: CLLocationCoordinate2D
    let to: CLLocationCoordinate2D

    static func == (lhs: SpikeTrip, rhs: SpikeTrip) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

extension SpikeTrip {
    static let portaVenezia = CLLocationCoordinate2D(latitude: 45.4746, longitude: 9.2050)
    static let politecnico = CLLocationCoordinate2D(latitude: 45.4781, longitude: 9.2272)
    static let duomo = CLLocationCoordinate2D(latitude: 45.4642, longitude: 9.1900)
    static let bicocca = CLLocationCoordinate2D(latitude: 45.5140, longitude: 9.2110)
    static let darsena = CLLocationCoordinate2D(latitude: 45.4520, longitude: 9.1757)
    static let sanSiro = CLLocationCoordinate2D(latitude: 45.4781, longitude: 9.1240)
    static let rhoFiera = CLLocationCoordinate2D(latitude: 45.5200, longitude: 9.0870)
    static let sanDonato = CLLocationCoordinate2D(latitude: 45.4140, longitude: 9.2690)
    /// ~120 m off the Porta Venezia → Politecnico line, standing in for a rider who missed a turn.
    static let offRoute = CLLocationCoordinate2D(latitude: 45.4775, longitude: 9.2140)

    static let primary = SpikeTrip(id: "Porta Venezia → Politecnico", from: portaVenezia, to: politecnico)

    static let benchmark: [SpikeTrip] = [
        primary,
        SpikeTrip(id: "Duomo → Bicocca", from: duomo, to: bicocca),
        SpikeTrip(id: "Darsena → Politecnico", from: darsena, to: politecnico),
        SpikeTrip(id: "Porta Venezia → San Siro", from: portaVenezia, to: sanSiro),
        SpikeTrip(id: "Rho Fiera → San Donato", from: rhoFiera, to: sanDonato),
        SpikeTrip(id: "Reroute: off route → Politecnico", from: offRoute, to: politecnico),
    ]
}
#endif
