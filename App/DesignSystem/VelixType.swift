import SwiftUI
import UIKit

/// One entry of the type scale (generated values in Generated/Font+Velix.swift).
struct VelixType: Sendable {
    let postScriptName: String
    let size: CGFloat
    let lineHeight: CGFloat
    let trackingEm: CGFloat
    let tabularNumbers: Bool
    /// Riding screens: Dynamic Type capped at 115 % (HANDOFF), sizes ≥ 30 pt don't scale.
    let riding: Bool
    let relativeTo: Font.TextStyle

    init(postScriptName: String, size: CGFloat, lineHeight: CGFloat, trackingEm: CGFloat, tabularNumbers: Bool,
                riding: Bool, relativeTo: Font.TextStyle) {
        self.postScriptName = postScriptName; self.size = size; self.lineHeight = lineHeight
        self.trackingEm = trackingEm; self.tabularNumbers = tabularNumbers; self.riding = riding; self.relativeTo = relativeTo
    }

    /// Riding sizes of 30 pt and more stay fixed; everything else follows Dynamic Type.
    var fixed: Bool { riding && size >= 30 }

    var font: Font {
        let f = fixed ? Font.custom(postScriptName, fixedSize: size) : Font.custom(postScriptName, size: size, relativeTo: relativeTo)
        return tabularNumbers ? f.monospacedDigit() : f
    }

    /// Extra space between lines so the line box matches the token's line height.
    var lineSpacing: CGFloat {
        let natural = UIFont(name: postScriptName, size: size)?.lineHeight ?? size * 1.2
        return max(0, lineHeight - natural)
    }
}

extension DynamicTypeSize {
    /// Riding screens cap Dynamic Type at 115 % (HANDOFF); xLarge is the closest step (≈ 112 %).
    static let velixRidingCap: DynamicTypeSize = .xLarge
    /// Other screens grow to XL (135 %) and reflow; xxxLarge is the closest step.
    static let velixScreenCap: DynamicTypeSize = .xxxLarge
}

private struct VelixTypeModifier: ViewModifier {
    let type: VelixType
    func body(content: Content) -> some View {
        let styled = content
            .font(type.font)
            .tracking(type.trackingEm * type.size)
            .lineSpacing(type.lineSpacing)
        if type.riding {
            styled.dynamicTypeSize(...DynamicTypeSize.velixRidingCap)
        } else {
            styled
        }
    }
}

extension View {
    /// Applies a Velix type token: font, tracking, line height, tabular figures and the Dynamic Type cap.
    func velixType(_ type: VelixType) -> some View { modifier(VelixTypeModifier(type: type)) }
}
