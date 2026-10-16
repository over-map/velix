import SwiftUI

/// EtaBar (P2 §08, S4/S5): arrival, minutes and km left, with the End button. Rerouting and arriving replace the
/// numbers with a status line.
struct EtaBar: View {
    enum State: Equatable {
        case normal(arrival: String, minutes: String, km: String)
        case rerouting
        case arriving(String)
    }
    let state: State
    var onEnd: () -> Void = {}

    var body: some View {
        HStack(spacing: 12) {
            switch state {
            case let .normal(arrival, minutes, km):
                HStack(spacing: 20) {
                    number(arrival, "arrival")
                    number(minutes, "min")
                    number(km, "km")
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Arrival \(arrival), \(minutes) minutes, \(km) kilometres left")
            case .rerouting:
                status(.loader, "Rerouting…", "Keep riding, new route in a moment")
            case let .arriving(place):
                status(.flag, "Arriving", place)
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
        .padding(EdgeInsets(top: 14, leading: 22, bottom: 22, trailing: CGFloat.velix.m))
        .background(Color.velix.surface, in: UnevenRoundedRectangle(topLeadingRadius: 26, topTrailingRadius: 26))
        .velixElevation(VelixElevations.e3, in: UnevenRoundedRectangle(topLeadingRadius: 26, topTrailingRadius: 26))
    }

    private func number(_ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).velixType(.ridingNumber).foregroundStyle(Color.velix.ink)
            Text(unit).velixType(VelixType.body.sized(13, lineHeight: 16)).foregroundStyle(Color.velix.ink3)
        }
        .fixedSize()
    }

    private func status(_ icon: VelixIcon, _ title: String, _ subtitle: String) -> some View {
        HStack(spacing: 10) {
            VelixIconView(icon, size: 28).foregroundStyle(Color.velix.ink)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).velixType(VelixType.ridingStreet.sized(24, lineHeight: 26)).foregroundStyle(Color.velix.ink)
                Text(subtitle).velixType(VelixType.body.sized(14, lineHeight: 18)).foregroundStyle(Color.velix.ink2)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    VStack(spacing: 16) {
        EtaBar(state: .normal(arrival: "08:42", minutes: "11", km: "2.6"))
        EtaBar(state: .rerouting)
        EtaBar(state: .arriving("Politecnico, on the right"))
    }
    .background(Color.velix.canvas)
}
