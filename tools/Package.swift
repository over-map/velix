// swift-tools-version:5.10
import PackageDescription

// Velix build tools (not shipped in the app).
//   swift run --package-path tools TokenGen design/velix-tokens.json App/DesignSystem/Generated
let package = Package(
    name: "VelixTools",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "TokenGen", targets: ["TokenGen"])],
    targets: [
        .target(name: "TokenGenCore"),
        .executableTarget(name: "TokenGen", dependencies: ["TokenGenCore"]),
        .testTarget(name: "TokenGenTests", dependencies: ["TokenGenCore"]),
    ]
)
