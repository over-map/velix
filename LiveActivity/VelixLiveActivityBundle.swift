import SwiftUI
import WidgetKit

@main
struct VelixLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        RideLiveActivity()
    }
}

/// Ride Live Activity: lock screen + Dynamic Island (P2 LiveActivity; views in Shared/RideActivityViews.swift).
/// The app starts and updates it in M7.
struct RideLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RideActivityAttributes.self) { context in
            LiveActivityLockScreen(state: context.state)
                .activityBackgroundTint(context.state.lockScreenBackground)
                .activitySystemActionForegroundColor(Color.velix.ink)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) { LiveActivityExpanded(state: context.state) }
            } compactLeading: {
                LiveActivityCompactLeading(state: context.state)
            } compactTrailing: {
                LiveActivityCompactTrailing(state: context.state)
            } minimal: {
                LiveActivityMinimal(state: context.state)
            }
        }
    }
}
