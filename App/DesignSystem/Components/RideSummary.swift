import SwiftUI

/// RideSummary (P2 §08, S8): after the ride. Distance, moving time and climb; sync status; share and done.
struct RideSummary: View {
    enum Sync: Equatable { case synced, notConnected }
    var km: String
    var minutes: String
    var climb: String
    var strava: Sync = .synced
    var health: Sync = .synced
    var onReport: () -> Void = {}
    var onShare: () -> Void = {}
    var onDone: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Ride complete").velixType(VelixType.title1.sized(28, lineHeight: 31)).foregroundStyle(Color.velix.ink)
            HStack(spacing: 22) {
                stat(km, "km")
                stat(minutes, "min moving")
                stat(climb, "m climb")
            }
            VStack(spacing: 0) {
                SyncRow(icon: .activity, name: "Strava", sync: strava, divider: false)
                SyncRow(icon: .heart, name: "Apple Health", sync: health)
                Button(action: onReport) {
                    ListRow(leading: .icon(.flag), title: "Report a data issue") {
                        VelixIconView(.chevronRight, size: 20).foregroundStyle(Color.velix.ink)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 10) {
                PrimaryButton(title: "Share GPX", icon: .share, kind: .secondary, action: onShare)
                PrimaryButton(title: "Done", action: onDone)
            }
        }
        .padding(CGFloat.velix.m)
        .background(Color.velix.surface, in: RoundedRectangle(cornerRadius: 24))
        .velixElevation(VelixElevations.e1, in: RoundedRectangle(cornerRadius: 24))
    }

    private func stat(_ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).velixType(VelixType.numberL.sized(28, lineHeight: 28)).foregroundStyle(Color.velix.ink)
            Text(unit).velixType(VelixType.body.sized(13, lineHeight: 16)).foregroundStyle(Color.velix.ink3)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Summary sync row: "✓ Synced", or "Not connected" with a link to You.
struct SyncRow: View {
    let icon: VelixIcon
    let name: String
    let sync: RideSummary.Sync
    var divider = true
    var onConnect: () -> Void = {}
    var body: some View {
        ListRow(leading: .icon(icon), title: name, subtitle: sync == .notConnected ? "Not connected" : nil, divider: divider) {
            switch sync {
            case .synced: StatusCheck(text: "Synced")
            case .notConnected: InlineLink(title: "Connect in You", action: onConnect)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// "Data issue reported" confirmation row (P2 RideSummary · with data issue).
struct DataIssueRow: View {
    let issue: String
    var body: some View {
        ListRow(leading: .icon(.flag), title: "Data issue reported", subtitle: issue, divider: false) {
            VelixIconView(.check, size: 20).foregroundStyle(Color.velix.success)
        }
        .accessibilityElement(children: .combine)
    }
}
