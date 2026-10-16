import Foundation
import TokenGenCore

// swift run --package-path tools TokenGen <tokens.json> <swift-out-dir> [<asset-catalog>] [--check]
//   --check: exit 1 if the files on disk differ from a fresh run (CI drift guard).
let args = CommandLine.arguments.dropFirst().filter { $0 != "--check" }
let check = CommandLine.arguments.contains("--check")
guard args.count >= 2 else {
    FileHandle.standardError.write(Data("usage: TokenGen <tokens.json> <swift-out-dir> [<asset-catalog>] [--check]\n".utf8))
    exit(2)
}
let tokensURL = URL(fileURLWithPath: args[args.startIndex])
let swiftDir = URL(fileURLWithPath: args[args.startIndex + 1])
let catalog = URL(fileURLWithPath: args.count > 2 ? args[args.startIndex + 2] : "App/Resources/Assets.xcassets")
let overridesURL = URL(fileURLWithPath: "tools/TokenGen/overrides.json")

do {
    let output = try TokenGen.generate(tokens: Data(contentsOf: tokensURL),
                                       overrides: try? Data(contentsOf: overridesURL))
    let fm = FileManager.default
    var drift: [String] = []
    func write(_ text: String, to url: URL) throws {
        if check {
            if (try? String(contentsOf: url, encoding: .utf8)) != text { drift.append(url.path) }
            return
        }
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
    let colorFolder = catalog.appending(path: "VelixColors")
    if !check, fm.fileExists(atPath: colorFolder.path) { try fm.removeItem(at: colorFolder) }  // drop stale colours
    for (path, text) in output.swift.sorted(by: { $0.key < $1.key }) { try write(text, to: swiftDir.appending(path: path)) }
    for (path, text) in output.assets.sorted(by: { $0.key < $1.key }) { try write(text, to: catalog.appending(path: path)) }
    if check {
        let expected = Set(output.assets.keys.filter { $0.hasSuffix(".colorset/Contents.json") }.map { $0.components(separatedBy: "/")[1] })
        let present = Set((try? fm.contentsOfDirectory(atPath: colorFolder.path))?.filter { $0.hasSuffix(".colorset") } ?? [])
        drift += present.subtracting(expected).map { "stale \($0)" }
        if !drift.isEmpty {
            print("Generated design tokens are out of date. Run TokenGen and commit:\n" + drift.joined(separator: "\n"))
            exit(1)
        }
        print("Design tokens up to date (\(output.swift.count) Swift files, \(output.assets.count) asset files)")
    } else {
        print("Wrote \(output.swift.count) Swift files and \(output.assets.count) asset files")
    }
} catch {
    FileHandle.standardError.write(Data("TokenGen: \(error)\n".utf8))
    exit(1)
}
