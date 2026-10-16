import SnapshotTesting
import SwiftUI
import XCTest
@testable import Velix

/// One snapshot per component state in `ComponentCatalog`, light and dark, at the state's P2 frame width.
/// Re-record with `SNAPSHOT_TESTING_RECORD=all` (see CLAUDE.md).
@MainActor
final class ComponentSnapshotTests: XCTestCase {
    private let precision: Float = 0.99
    private let perceptualPrecision: Float = 0.98

    func testSearchBar() { check("SearchBar") }
    func testRideTypeChip() { check("RideTypeChip") }
    func testRideTypePicker() { check("RideTypePicker") }
    func testMapStyleSheet() { check("MapStyleSheet") }
    func testMapButton() { check("MapButton") }
    func testRecenterButton() { check("RecenterButton") }
    func testNoticeBanner() { check("NoticeBanner") }
    func testRouteCard() { check("RouteCard") }
    func testComfortMixBar() { check("ComfortMixBar") }
    func testDifferenceLine() { check("DifferenceLine") }
    func testWhyThisRoute() { check("WhyThisRoute") }
    func testHazardMarker() { check("HazardMarker") }
    func testAvoidedTag() { check("AvoidedTag") }
    func testPrimaryButton() { check("PrimaryButton") }
    func testTabBar() { check("TabBar") }

    /// Every catalog component has a test above.
    func testCatalogCovered() {
        let tested = Set(Self.defaultTestSuite.tests.compactMap { ($0 as? XCTestCase)?.name })
        for c in ComponentCatalog.components {
            XCTAssertTrue(tested.contains { $0.contains("test\(c)]") }, "No snapshot test for \(c)")
        }
    }

    private func check(_ component: String, file: StaticString = #filePath, testName: String = #function, line: UInt = #line) {
        let entries = ComponentCatalog.entries.filter { $0.component == component }
        XCTAssertFalse(entries.isEmpty, "Unknown component \(component)")
        for entry in entries {
            for style in [UIUserInterfaceStyle.light, .dark] {
                let view = entry.view()
                    .frame(width: entry.width.map { $0 - 32 }, alignment: .leading)
                    .padding(16)
                    .background(Color.velix.canvas)
                let vc = UIHostingController(rootView: view)
                vc.overrideUserInterfaceStyle = style
                let size = vc.sizeThatFits(in: CGSize(width: entry.width ?? 393, height: 2000))
                assertSnapshot(of: vc, as: .image(on: .init(safeArea: .zero, size: size, traits: .init(userInterfaceStyle: style)),
                                                  precision: precision, perceptualPrecision: perceptualPrecision),
                               named: "\(entry.state)-\(style == .dark ? "dark" : "light")",
                               file: file, testName: testName, line: line)
            }
        }
    }
}
