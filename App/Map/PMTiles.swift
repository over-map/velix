import Compression
import Foundation

/// A read-only PMTiles v3 archive (https://github.com/protomaps/PMTiles/blob/main/spec/v3/spec.md): the pack's
/// basemap and overlays, read tile by tile so several packs can be served as one map (``PackTileProtocol``).
final class PMTiles: @unchecked Sendable {
    enum Failure: Error { case notPMTiles, unsupported(String) }
    enum Compression: UInt8 { case unknown = 0, none, gzip, brotli, zstd }

    struct Header: Equatable {
        var rootOffset: UInt64, rootLength: UInt64
        var leafOffset: UInt64, leafLength: UInt64
        var dataOffset: UInt64
        var internalCompression: Compression, tileCompression: Compression
        var minZoom: Int, maxZoom: Int
        /// [west, south, east, north]
        var bounds: [Double]
    }

    struct Entry: Equatable { var tileID: UInt64; var offset: UInt64; var length: UInt32; var runLength: UInt32 }

    let url: URL
    let header: Header
    private let file: FileHandle
    private let lock = NSLock()
    private var root: [Entry] = []
    private var leaves: [UInt64: [Entry]] = [:]

    init(url: URL) throws {
        self.url = url
        file = try FileHandle(forReadingFrom: url)
        let h = try file.read(at: 0, count: 127)
        header = try Self.header(h)
        root = try Self.directory(Self.decompress(try file.read(at: header.rootOffset, count: Int(header.rootLength)),
                                                  header.internalCompression))
    }

    deinit { try? file.close() }

    /// The tile's bytes as stored (gzip for tippecanoe's overlays, plain for the basemap), or nil if the archive has
    /// none there.
    func tile(z: Int, x: Int, y: Int) throws -> Data? {
        guard z >= header.minZoom, z <= header.maxZoom else { return nil }
        let id = Self.tileID(z: z, x: x, y: y)
        lock.lock(); defer { lock.unlock() }
        var dir = root
        for _ in 0 ..< 4 {
            guard let e = Self.find(id, in: dir) else { return nil }
            if e.runLength > 0 {
                return try file.read(at: header.dataOffset + e.offset, count: Int(e.length))
            }
            let key = header.leafOffset + e.offset
            if let cached = leaves[key] { dir = cached; continue }
            let leaf = try Self.directory(Self.decompress(try file.read(at: key, count: Int(e.length)), header.internalCompression))
            if leaves.count > 64 { leaves.removeAll() }
            leaves[key] = leaf
            dir = leaf
        }
        return nil
    }

    /// The tile decompressed (MVT bytes), for merging tiles of two packs.
    func vectorTile(z: Int, x: Int, y: Int) throws -> Data? {
        try tile(z: z, x: x, y: y).map { try Self.decompress($0, header.tileCompression) }
    }

    // MARK: Format

    static func header(_ d: Data) throws -> Header {
        guard d.count >= 127, d.prefix(7) == Data("PMTiles".utf8) else { throw Failure.notPMTiles }
        guard d[d.startIndex + 7] == 3 else { throw Failure.unsupported("version \(d[d.startIndex + 7])") }
        func u64(_ o: Int) -> UInt64 { d.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: o, as: UInt64.self).littleEndian } }
        func i32(_ o: Int) -> Int32 { d.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: o, as: Int32.self).littleEndian } }
        func u8(_ o: Int) -> UInt8 { d[d.startIndex + o] }
        return Header(rootOffset: u64(8), rootLength: u64(16), leafOffset: u64(40), leafLength: u64(48), dataOffset: u64(56),
                      internalCompression: Compression(rawValue: u8(97)) ?? .unknown,
                      tileCompression: Compression(rawValue: u8(98)) ?? .unknown,
                      minZoom: Int(u8(100)), maxZoom: Int(u8(101)),
                      bounds: [Double(i32(102)) / 1e7, Double(i32(106)) / 1e7, Double(i32(110)) / 1e7, Double(i32(114)) / 1e7])
    }

    static func directory(_ d: Data) throws -> [Entry] {
        var r = VarintReader(d)
        let n = Int(try r.next())
        var entries = [Entry](repeating: Entry(tileID: 0, offset: 0, length: 0, runLength: 0), count: n)
        var last: UInt64 = 0
        for i in 0 ..< n { last += try r.next(); entries[i].tileID = last }
        for i in 0 ..< n { entries[i].runLength = UInt32(try r.next()) }
        for i in 0 ..< n { entries[i].length = UInt32(try r.next()) }
        for i in 0 ..< n {
            let v = try r.next()
            entries[i].offset = v == 0 && i > 0 ? entries[i - 1].offset + UInt64(entries[i - 1].length) : v - 1
        }
        return entries
    }

    /// The entry covering `id`: the last one at or before it, if its run reaches it (or it points at a leaf).
    static func find(_ id: UInt64, in entries: [Entry]) -> Entry? {
        var lo = 0, hi = entries.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if entries[mid].tileID == id { return entries[mid] }
            if entries[mid].tileID < id { lo = mid + 1 } else { hi = mid - 1 }
        }
        guard hi >= 0 else { return nil }
        let e = entries[hi]
        if e.runLength == 0 { return e }
        return id - e.tileID < UInt64(e.runLength) ? e : nil
    }

    /// z/x/y → PMTiles tile id: the tiles of lower zooms, then the Hilbert index at z.
    static func tileID(z: Int, x: Int, y: Int) -> UInt64 {
        var acc: UInt64 = 0
        for i in 0 ..< z { acc += UInt64(1) << (2 * i) }
        let n = 1 << z
        var d: UInt64 = 0, x = x, y = y, s = n / 2
        while s > 0 {
            let rx = (x & s) > 0 ? 1 : 0, ry = (y & s) > 0 ? 1 : 0
            d += UInt64(s) * UInt64(s) * UInt64((3 * rx) ^ ry)
            if ry == 0 {
                if rx == 1 { x = s - 1 - x; y = s - 1 - y }
                swap(&x, &y)
            }
            s /= 2
        }
        return acc + d
    }

    static func decompress(_ d: Data, _ c: Compression) throws -> Data {
        switch c {
        case .none, .unknown: return d
        case .gzip: return try gunzip(d)
        default: throw Failure.unsupported("compression \(c)")
        }
    }

    /// gzip (RFC 1952) → bytes: the header skipped, then raw DEFLATE (Apple's COMPRESSION_ZLIB).
    static func gunzip(_ d: Data) throws -> Data {
        let b = [UInt8](d)
        guard b.count > 18, b[0] == 0x1F, b[1] == 0x8B else { return d }   // not gzip: as is
        let flags = b[3]
        var i = 10
        if flags & 4 != 0 { i += 2 + Int(b[i]) + Int(b[i + 1]) << 8 }      // FEXTRA
        if flags & 8 != 0 { while i < b.count, b[i] != 0 { i += 1 }; i += 1 }   // FNAME
        if flags & 16 != 0 { while i < b.count, b[i] != 0 { i += 1 }; i += 1 }  // FCOMMENT
        if flags & 2 != 0 { i += 2 }                                        // FHCRC
        let size = Int(UInt32(b[b.count - 4]) | UInt32(b[b.count - 3]) << 8 | UInt32(b[b.count - 2]) << 16 | UInt32(b[b.count - 1]) << 24)
        var out = [UInt8](repeating: 0, count: max(size, 1))
        let n = b[i...].withUnsafeBufferPointer { src in
            compression_decode_buffer(&out, out.count, src.baseAddress!, src.count, nil, COMPRESSION_ZLIB)
        }
        guard n > 0 || size == 0 else { throw Failure.unsupported("bad gzip") }
        return Data(out.prefix(n))
    }
}

/// Protobuf-style unsigned varints.
struct VarintReader {
    enum Failure: Error { case truncated }
    let bytes: [UInt8]
    var i = 0
    init(_ d: Data) { bytes = [UInt8](d) }
    var atEnd: Bool { i >= bytes.count }

    mutating func next() throws -> UInt64 {
        var v: UInt64 = 0, shift: UInt64 = 0
        while i < bytes.count {
            let b = bytes[i]; i += 1
            v |= UInt64(b & 0x7F) << shift
            if b < 0x80 { return v }
            shift += 7
        }
        throw Failure.truncated
    }
}

private extension FileHandle {
    /// `count` bytes from `offset` (fewer at the end of the file).
    func read(at offset: UInt64, count: Int) throws -> Data {
        try seek(toOffset: offset)
        return try read(upToCount: count) ?? Data()
    }
}
