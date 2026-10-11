import SnapshotTesting
import SwiftUI
import XCTest
@testable import Velix

@MainActor
final class LaunchViewSnapshotTests: XCTestCase {
    /// 393 × 852 pt, the design reference size (iPhone 15/16).
    private let size = CGSize(width: 393, height: 852)
    /// Tolerates anti-aliasing differences between local and CI simulator runtimes.
    private let precision: Float = 0.99
    private let perceptualPrecision: Float = 0.98

    func testLight() {
        assertSnapshot(of: host(.light), as: .image(on: .init(safeArea: .zero, size: size, traits: .init(userInterfaceStyle: .light)), precision: precision, perceptualPrecision: perceptualPrecision))
    }

    func testDark() {
        assertSnapshot(of: host(.dark), as: .image(on: .init(safeArea: .zero, size: size, traits: .init(userInterfaceStyle: .dark)), precision: precision, perceptualPrecision: perceptualPrecision))
    }

    private func host(_ style: UIUserInterfaceStyle) -> UIViewController {
        let vc = UIHostingController(rootView: LaunchView())
        vc.overrideUserInterfaceStyle = style
        return vc
    }
}
