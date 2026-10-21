import SwiftUI

/// RideSummary (P7 S6a–S6c): the sheet after a ride that ended by itself. A flag, the numbers, Strava and Apple
/// Health (synced, or Connect), at most one data-issue question, Share GPX and Done.
struct RideSummary: View {
    enum Connections: Equatable { case synced, notConnected }
    struct Issue: Equatable { var title: String; var message: String }

    /// "08:42"
    var arrived: String
    var place: String
    var rideType: RideType = .city
    /// "Calmest for city", "Fastest"
    var option: String
    var km: String
    var minutes: String
    var climb: String
    var connections: Connections = .notConnected
    var issue: Issue?
    /// The GPX to share; the button is hidden while it isn't written.
    var gpx: URL?
    var onConnect: () -> Void = {}
    var onReport: () -> Void = {}
    var onDone: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            head
            HStack(spacing: 28) {
                stat(km, "km")
                stat(minutes, "min moving")
                stat(climb, "m climb")
            }
            .accessibilityElement(children: .ignore)
            // P8: "5.4 kilometres, 21 minutes moving, 8 metres climb", grouped as one element.
            .accessibilityLabel("\(km) kilometres, \(minutes) minutes moving, \(climb) metres climb")
            switch connections {
            case .synced:
                HStack(spacing: 10) {
                    VelixIconView(.circleCheck, size: 22).foregroundStyle(Color.velix.success)
                    Text("Synced to Strava and Apple Health").velixType(VelixType.rowTitle.sized(16, lineHeight: 20))
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 48)
                .overlay(alignment: .top) { divider }
                .overlay(alignment: .bottom) { divider }
                .accessibilityElement(children: .combine)
            case .notConnected:
                VStack(spacing: 0) {
                    connectRow("Strava").overlay(alignment: .top) { divider }
                    connectRow("Apple Health")
                }
            }
            if let issue { issueCard(issue) }
            buttons
        }
        .foregroundStyle(Color.velix.ink)
    }

    private var head: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                VelixIconView(.flag, size: 18)
                Text("Arrived \(arrived)")
            }
            .velixType(VelixType.label.sized(14, lineHeight: 18))
            .foregroundStyle(Color.velix.success)
            Text(place).velixType(VelixType.title1.sized(28, lineHeight: 31)).lineLimit(2).accessibilityAddTraits(.isHeader)
            HStack(spacing: 6) {
                VelixIconView(rideType.glyph, size: 18)
                Text("\(rideType.name) · \(option)")
            }
            .velixType(VelixType.label.sized(14, lineHeight: 18))
            .foregroundStyle(Color.velix.ink2)
        }
        .accessibilityElement(children: .combine)
    }

    private var divider: some View { Rectangle().fill(Color.velix.line).frame(height: 1) }

    private func stat(_ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).velixType(VelixType.numberL.sized(34, lineHeight: 34))
            Text(unit).velixType(VelixType.body.sized(14, lineHeight: 17)).foregroundStyle(Color.velix.ink3)
        }
    }

    /// "Save to Strava" with Connect (connections live in You, M9).
    private func connectRow(_ name: String) -> some View {
        HStack(spacing: 10) {
            Text("Save to \(name)").velixType(VelixType.rowTitle.sized(16, lineHeight: 20))
            Spacer(minLength: 0)
            outlined("Connect", label: "Connect \(name)", action: onConnect)
        }
        .frame(minHeight: 52)
        .overlay(alignment: .bottom) { divider }
    }

    private func issueCard(_ issue: Issue) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VelixIconView(.messageSquareWarning, size: 22)
            VStack(alignment: .leading, spacing: 4) {
                Text(issue.title).velixType(VelixType.rowTitle.sized(16, lineHeight: 21))
                Text(issue.message).velixType(VelixType.body.sized(14, lineHeight: 20)).foregroundStyle(Color.velix.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            outlined("Report", label: "\(issue.title). Report", action: onReport)
        }
        .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
        .background(Color.velix.surface2, in: RoundedRectangle(cornerRadius: 16))
    }

    private func outlined(_ title: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).velixType(VelixType.label.sized(15, lineHeight: 19))
                .padding(.horizontal, 14).frame(minHeight: 36)
                .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(Color.velix.ink, lineWidth: 1.5) }
                .contentShape(Rectangle())
        }
        .buttonStyle(VelixPressStyle())
        .foregroundStyle(Color.velix.ink)
        .frame(minHeight: 44)
        .accessibilityLabel(label)
    }

    private var buttons: some View {
        HStack(spacing: 10) {
            if let gpx {
                ShareLink(item: gpx) {
                    HStack(spacing: 10) {
                        VelixIconView(.share, size: 22)
                        Text("Share GPX").velixType(.button)
                    }
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .foregroundStyle(Color.velix.ink)
                    .overlay { RoundedRectangle(cornerRadius: CGFloat.velix.radius.card).strokeBorder(Color.velix.line, lineWidth: 1.5) }
                    .contentShape(Rectangle())
                }
                .buttonStyle(VelixPressStyle())
            }
            PrimaryButton(title: "Done", kind: .ink, action: onDone)
        }
    }
}

extension RideSummary {
    /// P7 S6c copy (the check behind it comes in M9).
    static let sampleIssue = Issue(title: "Via Pascoli felt different",
                                   message: "It’s marked as cobbles, but you rode it at your usual speed. Was it resurfaced?")
}
