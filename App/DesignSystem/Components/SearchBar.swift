import SwiftUI

/// SearchBar (P2 §08, S1/S2): idle with Home / Work, unset Home or Work, focused with Cancel.
struct SearchBar: View {
    var homeSet = true
    var workSet = true
    var onHome: () -> Void = {}
    var onWork: () -> Void = {}
    var onTap: () -> Void = {}

    var body: some View {
        HStack(spacing: CGFloat.velix.xs) {
            Button(action: onTap) {
                HStack(spacing: CGFloat.velix.xs) {
                    VelixIconView(.search, size: 20).foregroundStyle(Color.velix.ink)
                    Text("Where to?").velixType(.body).foregroundStyle(Color.velix.ink2)
                    Spacer(minLength: 0)
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Search a place")
            shortcut(set: homeSet, title: "Home", setTitle: "Set Home", icon: .house, action: onHome)
            shortcut(set: workSet, title: "Work", setTitle: "Set Work", icon: .briefcase, action: onWork)
        }
        .padding(EdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 6))
        .frame(height: 56)
        .background(Color.velix.surface, in: RoundedRectangle(cornerRadius: CGFloat.velix.radius.card))
        .velixElevation(VelixElevations.e1)
    }

    private func shortcut(set: Bool, title: String, setTitle: String, icon: VelixIcon, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                VelixIconView(set ? icon : .plus, size: 18)
                Text(set ? title : setTitle).velixType(.label)
            }
            .padding(.horizontal, CGFloat.velix.s)
            .frame(height: CGFloat.velix.touch.min)
            .foregroundStyle(Color.velix.ink)
            .background(set ? Color.velix.surface2 : .clear, in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                if !set { RoundedRectangle(cornerRadius: 12).strokeBorder(Color.velix.line, lineWidth: 1.5) }
            }
        }
        .buttonStyle(VelixPressStyle())
        .accessibilityLabel(set ? "Go \(title.lowercased())" : setTitle)
    }
}

/// Focused search field (S2): ink ring, clear button, Cancel.
struct SearchField: View {
    @Binding var text: String
    var onCancel: () -> Void = {}
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: CGFloat.velix.s) {
            HStack(spacing: 10) {
                VelixIconView(.search, size: 20).foregroundStyle(Color.velix.ink)
                TextField("Where to?", text: $text)
                    .velixType(.body)
                    .foregroundStyle(Color.velix.ink)
                    .tint(Color.velix.ink)
                    .focused($focused)
                    .submitLabel(.search)
                if !text.isEmpty {
                    Button { text = "" } label: { VelixIconView(.circleX, size: 20).foregroundStyle(Color.velix.ink3) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear")
                }
            }
            .padding(.horizontal, CGFloat.velix.s)
            .frame(height: 52)
            .background(Color.velix.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.velix.ink, lineWidth: 2))
            Button("Cancel", action: onCancel)
                .velixType(.bodyBold)
                .foregroundStyle(Color.velix.ink)
                .frame(minHeight: CGFloat.velix.touch.min)
        }
        .onAppear { focused = true }
    }
}

#Preview {
    VStack(spacing: 20) {
        SearchBar()
        SearchBar(homeSet: false)
        SearchField(text: .constant("Polit"))
    }
    .padding().background(Color.velix.canvas)
}
