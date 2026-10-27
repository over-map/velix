import SwiftUI

/// EtaBar (P2 §08, P5 S4/S5): arrival, minutes and km left, with the End button. Rerouting and arriving replace the
/// numbers with a status line (S4g "New route", S4i "Arriving").
struct EtaBar: View {
    enum State: Equatable {
        case normal(arrival: String, minutes: String, km: String)
        /// After three failed tries (M7a): the old route stays and the bar says so.
        case rerouting(cannotFind: Bool)
        case arriving
        /// Bike + transit, stage 1 (P6 S5a–c): arrival at the station, the train and the spare time.
        case transit(arrival: String, at: String, train: String, spare: String?, tight: Bool)
    }
    let state: State
    var onEnd: () -> Void = {}

    var body: some View {
        HStack(spacing: 12) {
            switch state {
            case let .normal(arrival, minutes, km):
                HStack(spacing: 22) {
                    number(arrival, "arrival")
                    number(minutes, "min")
                    number(km, "km")
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Arrive \(arrival), \(minutes) minutes, \(km) kilometres")
            case let .rerouting(cannotFind):
                cannotFind ? status(.routeOff, "No new route yet", "Keep riding, still trying")
                    : status(.route, "New route", "Ready in a moment")
            case .arriving:
                status(.flag, "Arriving", "Ride ends by itself")
            case let .transit(arrival, at, train, spare, tight):
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(arrival).velixType(.ridingNumber).foregroundStyle(Color.velix.ink)
                        Text("at \(at)").velixType(VelixType.ridingLabel.sized(17, lineHeight: 21)).foregroundStyle(Color.velix.ink)
                            .lineLimit(1)
                    }
                    HStack(spacing: 6) {
                        VelixIconView(.trainFront, size: 18)
                        Text(train)
                        if let spare {
                            Text(spare).bold().foregroundStyle(tight ? Color.velix.warningInk : Color.velix.success)
                        }
                    }
                    .velixType(VelixType.body.sized(15, lineHeight: 19)).foregroundStyle(Color.velix.ink2).lineLimit(1)
                }
                .accessibilityElement(children: .combine)
            }
            Spacer(minLength: 0)
            Button(action: onEnd) {
                Text("End").velixType(.button).foregroundStyle(Color.velix.dangerInk)
                    .frame(width: 92, height: CGFloat.velix.touch.riding)
                    .background(Color.velix.danger, in: RoundedRectangle(cornerRadius: CGFloat.velix.radius.card))
            }
            .buttonStyle(VelixPressStyle())
            .accessibilityLabel("End ride")
        }
        .padding(EdgeInsets(top: 14, leading: 22, bottom: 34, trailing: 16))
        .background(Color.velix.surface, in: UnevenRoundedRectangle(topLeadingRadius: 26, topTrailingRadius: 26))
        .velixElevation(VelixElevations.e3, in: UnevenRoundedRectangle(topLeadingRadius: 26, topTrailingRadius: 26))
    }

    private func number(_ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).velixType(.ridingNumber).foregroundStyle(Color.velix.ink)
            Text(unit).velixType(VelixType.body.sized(14, lineHeight: 17)).foregroundStyle(Color.velix.ink3)
        }
        .fixedSize()
    }

    private func status(_ icon: VelixIcon, _ title: String, _ subtitle: String) -> some View {
        HStack(spacing: 12) {
            VelixIconView(icon, size: 30).foregroundStyle(Color.velix.ink)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).velixType(VelixType.ridingStreet.sized(26, lineHeight: 29)).foregroundStyle(Color.velix.ink).lineLimit(1)
                Text(subtitle).velixType(VelixType.body.sized(15, lineHeight: 19)).foregroundStyle(Color.velix.ink2).lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    VStack(spacing: 16) {
        EtaBar(state: .normal(arrival: "08:42", minutes: "11", km: "2.6"))
        EtaBar(state: .rerouting(cannotFind: false))
        EtaBar(state: .rerouting(cannotFind: true))
        EtaBar(state: .arriving)
        EtaBar(state: .transit(arrival: "08:12", at: "Centrale", train: "08:16 · platform planned ·", spare: "4 min to spare", tight: false))
    }
    .background(Color.velix.canvas)
}
