// One z17 tile of every aerial source at its test point, fetched with URLSession (the app's TLS: some agencies send
// certificate chains that curl and Python reject but Apple's trust evaluation completes).
// Usage: swift tools/imagery/online.swift App/Resources/Imagery/aerial-sources.json   (via imagery.py --online)
import Foundation

struct Table: Decodable { struct S: Decodable { let id: String; let url: String; let test: [Double] }; let sources: [S] }
let table = try JSONDecoder().decode(Table.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))

func address(_ t: String, z: Int, x: Int, y: Int) -> URL {
    let n = 1 << z, half = 20_037_508.342789244, size = 2 * half / Double(n)
    let b = [Double(x) * size - half, half - Double(y + 1) * size, Double(x + 1) * size - half, half - Double(y) * size]
    return URL(string: t.replacingOccurrences(of: "{z}", with: "\(z)").replacingOccurrences(of: "{x}", with: "\(x)")
        .replacingOccurrences(of: "{-y}", with: "\(n - 1 - y)").replacingOccurrences(of: "{y}", with: "\(y)")
        .replacingOccurrences(of: "{bbox}", with: b.map { String(format: "%.2f", $0) }.joined(separator: ",")))!
}

let config = URLSessionConfiguration.ephemeral
config.httpAdditionalHeaders = ["User-Agent": "Velix (+https://github.com/over-map/velix)"]
config.timeoutIntervalForRequest = 30
let session = URLSession(configuration: config)
let group = DispatchGroup()
let lock = NSLock()
var failed: [String] = []
for s in table.sources {
    let z = 17, n = Double(1 << z), lat = s.test[0] * .pi / 180
    let x = Int((s.test[1] + 180) / 360 * n), y = Int((1 - asinh(tan(lat)) / .pi) / 2 * n)
    group.enter()
    session.dataTask(with: address(s.url, z: z, x: x, y: y)) { data, response, error in
        let h = response as? HTTPURLResponse
        let type = h?.value(forHTTPHeaderField: "Content-Type") ?? "-"
        let ok = h?.statusCode == 200 && type.hasPrefix("image/") && (data?.count ?? 0) > 2_000
        lock.withLock {
            print("\(ok ? "ok  " : "FAIL") \(s.id.padding(toLength: 8, withPad: " ", startingAt: 0)) \(h?.statusCode ?? -1) \(type) \(data?.count ?? 0) B \(error?.localizedDescription ?? "")")
            if !ok { failed.append(s.id) }
        }
        group.leave()
    }.resume()
}
group.wait()
if !failed.isEmpty { print("Failed: \(failed.joined(separator: ", "))"); exit(1) }
print("All \(table.sources.count) sources served a tile.")
