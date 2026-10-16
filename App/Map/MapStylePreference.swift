import Foundation

/// The map style chosen in MapStyleSheet, remembered per ride type (BUILD_PLAN M5). City / Road / Cargo default to
/// Standard, Gravel / MTB / E-bike to Outdoor; a type can only keep a style its sheet offers.
struct MapStylePreference {
    var defaults: UserDefaults = .standard

    func style(for type: RideType) -> MapStyleSheet.Style {
        let offered = MapStyleSheet.styles(for: type)
        if let raw = defaults.string(forKey: key(type)), let s = MapStyleSheet.Style(rawValue: raw), offered.contains(s) { return s }
        return offered[0]
    }

    func set(_ style: MapStyleSheet.Style, for type: RideType) {
        defaults.set(style.rawValue, forKey: key(type))
    }

    private func key(_ type: RideType) -> String { "velix.mapStyle.\(type.rawValue)" }
}
