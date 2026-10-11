import SwiftUI
import UIKit

// TEMPORARY (M0). The few values from design/velix-tokens.json needed by the
// placeholder launch view. Delete when TokenGen generates Color/Font.velix in M4.
enum Bootstrap {
    enum Color {
        /// tokens: color.canvas
        static let canvas = dynamic(light: 0xF7F7EF, dark: 0x021624)
        /// tokens: color.ink
        static let ink = dynamic(light: 0x021624, dark: 0xEEEDD6)

        private static func dynamic(light: UInt32, dark: UInt32) -> SwiftUI.Color {
            SwiftUI.Color(UIColor { traits in
                UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
            })
        }
    }

    enum Font {
        /// PostScript names of the bundled fonts (App/Resources/Fonts).
        static let postScriptNames = [
            "AtkinsonHyperlegible-Regular",
            "AtkinsonHyperlegible-Bold",
            "FamiljenGroteskRoman-Medium",
            "FamiljenGroteskRoman-SemiBold",
            "FamiljenGroteskRoman-Bold",
        ]

        /// tokens: font.display (Familjen Grotesk 700, 34/40, -0.01em, full Dynamic Type range)
        static let display = SwiftUI.Font.custom("FamiljenGroteskRoman-Bold", size: 34, relativeTo: .largeTitle)
        static let displayTracking: CGFloat = 34 * -0.01
        /// tokens: font.body (Atkinson Hyperlegible 400, 17/24, full Dynamic Type range)
        static let body = SwiftUI.Font.custom("AtkinsonHyperlegible-Regular", size: 17, relativeTo: .body)
    }

    enum Spacing {
        /// tokens: spacing.xs
        static let xs: CGFloat = 8
    }
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
