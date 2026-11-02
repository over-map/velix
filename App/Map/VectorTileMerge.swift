import Foundation

/// Joins Mapbox Vector Tiles (spec 2.1) from two packs into one: at a region border both packs have the tile, each
/// with only its own side's features. Layers of the same name become one layer: the second layer's keys and values
/// are appended and its features' tag indices moved past the first's. Everything else is copied as is.
enum VectorTileMerge {
    /// One protobuf field: number, wire type, and its payload (varint value, or the bytes of a length-delimited field).
    private struct Field { var number: Int; var wire: Int; var varint: UInt64 = 0; var bytes: ArraySlice<UInt8> = [] }

    private struct Layer {
        var name = ""
        var version: UInt64 = 2
        var extent: UInt64 = 4096
        var keys: [ArraySlice<UInt8>] = []
        var values: [ArraySlice<UInt8>] = []
        var features: [ArraySlice<UInt8>] = []
        /// Tag index shift per feature (its layer's offsets once merged).
        var shifts: [(keys: UInt64, values: UInt64)] = []
    }

    static func merge(_ tiles: [Data]) -> Data {
        guard tiles.count > 1 else { return tiles.first ?? Data() }
        var order: [String] = []
        var layers: [String: Layer] = [:]
        for tile in tiles {
            for f in fields([UInt8](tile)[...]) where f.number == 3 && f.wire == 2 {
                let l = layer(f.bytes)
                if var m = layers[l.name] {
                    let shift = (UInt64(m.keys.count), UInt64(m.values.count))
                    m.keys += l.keys
                    m.values += l.values
                    m.features += l.features
                    m.shifts += Array(repeating: shift, count: l.features.count)
                    layers[l.name] = m
                } else {
                    var l = l
                    l.shifts = Array(repeating: (0, 0), count: l.features.count)
                    layers[l.name] = l
                    order.append(l.name)
                }
            }
        }
        var out: [UInt8] = []
        for name in order {
            let l = layers[name]!
            var body: [UInt8] = []
            putVarint(15 << 3, &body); putVarint(l.version, &body)
            putBytes(1, Array(l.name.utf8)[...], &body)
            for (f, s) in zip(l.features, l.shifts) { putBytes(2, s == (0, 0) ? f : shifted(f, s), &body) }
            for k in l.keys { putBytes(3, k, &body) }
            for v in l.values { putBytes(4, v, &body) }
            putVarint(5 << 3, &body); putVarint(l.extent, &body)
            putBytes(3, body[...], &out)
        }
        return Data(out)
    }

    private static func layer(_ b: ArraySlice<UInt8>) -> Layer {
        var l = Layer()
        for f in fields(b) {
            switch (f.number, f.wire) {
            case (1, 2): l.name = String(decoding: f.bytes, as: UTF8.self)
            case (2, 2): l.features.append(f.bytes)
            case (3, 2): l.keys.append(f.bytes)
            case (4, 2): l.values.append(f.bytes)
            case (5, 0): l.extent = f.varint
            case (15, 0): l.version = f.varint
            default: break
            }
        }
        return l
    }

    /// The feature with its tags (field 2: packed key, value index pairs) moved by the layer offsets.
    private static func shifted(_ feature: ArraySlice<UInt8>, _ s: (keys: UInt64, values: UInt64)) -> ArraySlice<UInt8> {
        var out: [UInt8] = []
        for f in fields(feature) {
            if f.number == 2, f.wire == 2 {
                var r = VarintReader(Data(f.bytes))
                var tags: [UInt8] = []
                var even = true
                while !r.atEnd, let v = try? r.next() {
                    putVarint(v + (even ? s.keys : s.values), &tags)
                    even.toggle()
                }
                putBytes(2, tags[...], &out)
            } else if f.wire == 0 {
                putVarint(UInt64(f.number << 3), &out); putVarint(f.varint, &out)
            } else {
                putBytes(f.number, f.bytes, &out)
            }
        }
        return out[...]
    }

    /// The fields of a message (varint and length-delimited only: all MVT uses).
    private static func fields(_ b: ArraySlice<UInt8>) -> [Field] {
        var out: [Field] = []
        var i = b.startIndex
        func varint() -> UInt64? {
            var v: UInt64 = 0, shift: UInt64 = 0
            while i < b.endIndex {
                let x = b[i]; i += 1
                v |= UInt64(x & 0x7F) << shift
                if x < 0x80 { return v }
                shift += 7
            }
            return nil
        }
        while i < b.endIndex, let key = varint() {
            var f = Field(number: Int(key >> 3), wire: Int(key & 7))
            switch f.wire {
            case 0: guard let v = varint() else { return out }; f.varint = v
            case 2:
                guard let n = varint(), i + Int(n) <= b.endIndex else { return out }
                f.bytes = b[i ..< i + Int(n)]; i += Int(n)
            case 1: i += 8; continue
            case 5: i += 4; continue
            default: return out
            }
            out.append(f)
        }
        return out
    }

    private static func putVarint(_ v: UInt64, _ out: inout [UInt8]) {
        var v = v
        while v >= 0x80 { out.append(UInt8(v & 0x7F) | 0x80); v >>= 7 }
        out.append(UInt8(v))
    }

    private static func putBytes(_ number: Int, _ b: ArraySlice<UInt8>, _ out: inout [UInt8]) {
        putVarint(UInt64(number << 3 | 2), &out)
        putVarint(UInt64(b.count), &out)
        out += b
    }
}
