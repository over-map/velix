import SwiftUI

/// DifferenceLine (P2 §08): how Best compares with Fastest, in words. `**…**` marks the bold lead ("**+5 min** · avoids
/// 420 m cobbles, 3 rail crossings"; "Fastest is **only 40 s quicker**, with 2 rail crossings").
struct DifferenceLine: View {
    let text: String
    var standalone = false

    var body: some View {
        Text(attributed)
            .velixType(standalone ? VelixType.callout : VelixType.detail)
            .foregroundStyle(Color.velix.ink2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var attributed: AttributedString {
        var out = AttributedString()
        for (i, part) in text.components(separatedBy: "**").enumerated() {
            var a = AttributedString(part)
            if i % 2 == 1 {
                a.font = Font.custom(VelixType.bodyBold.postScriptName, size: standalone ? 15 : 14, relativeTo: .callout)
                a.foregroundColor = Color.velix.ink
            }
            out += a
        }
        return out
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 12) {
        DifferenceLine(text: "**+5 min** · avoids 420 m cobbles, 3 rail crossings", standalone: true)
        DifferenceLine(text: "Fastest is **only 40 s quicker**, with 2 rail crossings", standalone: true)
    }
    .padding().background(Color.velix.canvas)
}
