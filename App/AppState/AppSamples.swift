#if DEBUG
import Foundation

/// P4 sample places and notices (Milan), for previews and snapshot tests.
enum AppSamples {
    static let home = Place(id: "home", name: "Porta Venezia", subtitle: "Milan", kind: .address, lat: 45.4762, lon: 9.2047)
    static let work = Place(id: "work", name: "Politecnico, Città Studi", subtitle: "Piazza Leonardo da Vinci", kind: .poi,
                            lat: 45.4781, lon: 9.2272)
    static let recents = [
        Place(id: "r1", name: "Milano Centrale", subtitle: "Railway station", kind: .station, lat: 45.4859, lon: 9.2040),
        Place(id: "r2", name: "Villa Reale", subtitle: "Monza", kind: .park, lat: 45.5915, lon: 9.2747),
        Place(id: "r3", name: "Piazza Leonardo da Vinci", subtitle: "Città Studi", kind: .poi, lat: 45.4782, lon: 9.2271),
    ]
    static let centrResults = [
        Place(id: "c1", name: "Milano Centrale", subtitle: "Railway station · Piazza Duca d’Aosta", kind: .station, lat: 45.4859, lon: 9.2040),
        Place(id: "c2", name: "Centrale", subtitle: "Metro station", kind: .metro, lat: 45.4848, lon: 9.2048, lines: ["M2", "M3"], lineFamilies: ["green", "yellow"]),
        Place(id: "c3", name: "Piazza Duca d’Aosta", subtitle: "Square by Milano Centrale", kind: .poi, lat: 45.4850, lon: 9.2040),
    ]
    static let storm = WeatherWarning(title: "Severe weather in Milan", message: "Thunderstorms until 18:00. Take care if you ride.",
                                      pill: "Storm until 18:00")
}
#endif
