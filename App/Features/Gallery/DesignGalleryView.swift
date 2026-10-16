#if DEBUG
import SwiftUI

/// Debug screen: every component state in P2 order, to compare against `design/Velix P2 Design System v2.dc.html`.
/// Open with the `-design-gallery` launch argument.
struct DesignGalleryView: View {
    @State private var dark = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: CGFloat.velix.l) {
                HStack {
                    Text("Design system").velixType(.title2).foregroundStyle(Color.velix.ink)
                    Spacer()
                    Toggle(isOn: $dark) { Text("Dark").velixType(.label).foregroundStyle(Color.velix.ink) }
                        .toggleStyle(VelixToggleStyle()).fixedSize()
                }
                ForEach(ComponentCatalog.components, id: \.self) { name in
                    VStack(alignment: .leading, spacing: CGFloat.velix.s) {
                        SectionLabel(name)
                        ForEach(ComponentCatalog.entries.filter { $0.component == name }) { entry in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.state).velixType(.caption).foregroundStyle(Color.velix.ink3)
                                entry.view()
                            }
                        }
                    }
                }
            }
            .padding(CGFloat.velix.m)
        }
        .background(Color.velix.canvas)
        .preferredColorScheme(dark ? .dark : .light)
    }
}

#Preview { DesignGalleryView() }
#endif
