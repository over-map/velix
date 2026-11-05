import Foundation

/// The kind of place a POI is, in words ("Café", "Bike shop"), from its OSM value: OpenMapTiles' `subclass` on the
/// map, Photon's `osm_value` in search (Filippo, 5 Nov: tap or search a POI and route to it).
enum PoiCategory {
    private static let names: [String: String] = [
        "cafe": "Café", "restaurant": "Restaurant", "bar": "Bar", "pub": "Pub", "fast_food": "Fast food",
        "ice_cream": "Ice cream", "bakery": "Bakery", "beer": "Beer shop", "food_court": "Food court",
        "supermarket": "Supermarket", "convenience": "Shop", "grocery": "Grocery", "greengrocer": "Greengrocer",
        "butcher": "Butcher", "deli": "Deli", "marketplace": "Market", "mall": "Shopping centre",
        "department_store": "Department store", "clothes": "Clothes shop", "clothing_store": "Clothes shop",
        "shoes": "Shoe shop", "books": "Bookshop", "florist": "Florist", "hairdresser": "Hairdresser",
        "bicycle": "Bike shop", "bicycle_parking": "Bike parking", "bicycle_rental": "Bike rental",
        "bicycle_repair_station": "Bike repair stand", "compressed_air": "Air pump", "drinking_water": "Drinking water",
        "pharmacy": "Pharmacy", "chemist": "Chemist", "hospital": "Hospital", "clinic": "Clinic", "doctors": "Doctor",
        "dentist": "Dentist", "veterinary": "Vet",
        "museum": "Museum", "gallery": "Gallery", "theatre": "Theatre", "cinema": "Cinema", "library": "Library",
        "arts_centre": "Arts centre", "attraction": "Attraction", "viewpoint": "Viewpoint", "castle": "Castle",
        "monument": "Monument", "memorial": "Memorial", "artwork": "Artwork", "zoo": "Zoo",
        "place_of_worship": "Place of worship", "church": "Church", "cathedral": "Cathedral", "chapel": "Chapel",
        "school": "School", "university": "University", "college": "College", "kindergarten": "Kindergarten",
        "hotel": "Hotel", "hostel": "Hostel", "guest_house": "Guest house", "camp_site": "Campsite", "motel": "Motel",
        "park": "Park", "garden": "Garden", "playground": "Playground", "sports_centre": "Sports centre",
        "stadium": "Stadium", "swimming_pool": "Swimming pool", "pitch": "Sports pitch",
        "town_hall": "Town hall", "police": "Police", "post_office": "Post office", "bank": "Bank", "atm": "ATM",
        "toilets": "Toilets", "fuel": "Fuel", "parking": "Parking", "information": "Information",
        "station": "Railway station", "halt": "Railway station", "subway": "Metro station", "bus_station": "Bus station",
        "ferry_terminal": "Ferry terminal",
    ]

    /// Values that say nothing about the place.
    private static let vague: Set<String> = ["yes", "no", "other", "unknown", "", "attraction_other"]

    /// "Café"; unknown values read as words ("ice_rink" → "Ice rink"); `nil` for vague ones.
    static func name(_ value: String?) -> String? {
        guard let value = value?.lowercased(), !vague.contains(value) else { return nil }
        if let n = names[value] { return n }
        let words = value.replacingOccurrences(of: "_", with: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }
}
