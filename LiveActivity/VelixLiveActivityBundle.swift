import SwiftUI
import WidgetKit

@main
struct VelixLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        RideLiveActivity()
    }
}

/// Placeholder until M7 (Live Activity + Dynamic Island from P5).
struct RideLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RideActivityAttributes.self) { _ in
            Text("Velix")
        } dynamicIsland: { _ in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) { Text("Velix") }
            } compactLeading: {
                EmptyView()
            } compactTrailing: {
                EmptyView()
            } minimal: {
                EmptyView()
            }
        }
    }
}
