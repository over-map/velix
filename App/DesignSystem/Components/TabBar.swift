import SwiftUI

/// TabBar (P2 §08): Ride, Routes, You.
struct TabBar: View {
    enum Tab: String, CaseIterable { case ride = "Ride", routes = "Routes", you = "You" }
    var selected: Tab = .ride
    var onSelect: (Tab) -> Void = { _ in }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.self) { tab in
                Button { onSelect(tab) } label: {
                    VStack(spacing: 3) {
                        icon(tab)
                        Text(tab.rawValue).velixType(.tabLabel)
                    }
                    .frame(maxWidth: .infinity, minHeight: CGFloat.velix.touch.min)
                    .foregroundStyle(tab == selected ? Color.velix.ink : Color.velix.ink3)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.rawValue)
                .accessibilityAddTraits(tab == selected ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(.top, CGFloat.velix.xs)
        .padding(.bottom, 26)
        .background(Color.velix.surface)
        .overlay(alignment: .top) { Rectangle().fill(Color.velix.line).frame(height: 1) }
    }

    @ViewBuilder private func icon(_ tab: Tab) -> some View {
        switch tab {
        case .ride: VelixIconView(.navigation, size: 26)
        case .routes: VelixIconView(.route, size: 26)
        case .you: VelixIconView(.userRound, size: 26)
        }
    }
}

#Preview { TabBar().background(Color.velix.canvas) }
