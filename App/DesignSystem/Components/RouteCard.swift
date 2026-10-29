import SwiftUI

/// RouteCard (P2 §08, S3): Best selected, Fastest unselected, Best and fastest, computing. No score (HANDOFF).
struct RouteCard: View {
    struct Model: Equatable {
        var name: String
        var distance: String
        var minutes: Int
        var mix: [MixCategory: Double]
        /// DifferenceLine text with `**bold**` lead; nil on an unselected Fastest card.
        var line: String?
        var selected: Bool
        /// Long rides (S7d): "2 h 20" instead of minutes.
        var time: String?
    }

    let model: Model
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(model.name).velixType(.cardTitle).foregroundStyle(Color.velix.ink)
                        Text(model.distance).velixType(.footnote).foregroundStyle(Color.velix.ink3)
                    }
                    Spacer(minLength: CGFloat.velix.xs)
                    Text(model.time ?? "\(model.minutes) min")
                        .velixType(model.selected ? .numberL : .numberM)
                        .foregroundStyle(Color.velix.ink)
                        .lineLimit(1)
                }
                ComfortMixBar(mix: model.mix, size: model.selected ? .large : .compact)
                if let line = model.line { DifferenceLine(text: line) }
            }
            .padding(.horizontal, 14).padding(.vertical, CGFloat.velix.s)
            .background(Color.velix.surface, in: RoundedRectangle(cornerRadius: CGFloat.velix.radius.card))
            .overlay(RoundedRectangle(cornerRadius: CGFloat.velix.radius.card)
                .strokeBorder(model.selected ? Color.velix.ink : Color.velix.line, lineWidth: model.selected ? 2 : 1))
            .velixElevation(model.selected ? VelixElevations.e2 : VelixElevations.e0)
        }
        .buttonStyle(VelixPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(model.name), \(model.minutes) minutes, \(model.distance)")
        .accessibilityAddTraits(model.selected ? [.isSelected, .isButton] : .isButton)
    }
}

/// RouteCard while routes are computing: skeleton bars.
struct RouteCardSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                bar(150, 16)
                Spacer()
                bar(70, 24)
            }
            bar(60, 12)
            bar(nil, 8)
        }
        .padding(14)
        .overlay(RoundedRectangle(cornerRadius: CGFloat.velix.radius.card).strokeBorder(Color.velix.line, lineWidth: 1))
        .accessibilityLabel("Finding routes")
    }

    private func bar(_ width: CGFloat?, _ height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 4).fill(Color.velix.surface2).frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }
}

extension RouteCard.Model {
    /// Sample data from P2 (illustrative).
    static let sampleBest = RouteCard.Model(name: "Calmest for city", distance: "5.4 km", minutes: 23,
                                            mix: [.protected: 45, .painted: 25, .quiet: 25, .mixed: 5],
                                            line: "**+5 min** · avoids 420 m cobbles, 3 rail crossings", selected: true)
    static let sampleFastest = RouteCard.Model(name: "Fastest", distance: "4.6 km", minutes: 18,
                                               mix: [.protected: 15, .painted: 20, .quiet: 10, .mixed: 40, .cobbles: 15],
                                               line: nil, selected: false)
    static let sampleSingle = RouteCard.Model(name: "Best and fastest", distance: "3.1 km", minutes: 12,
                                              mix: [.protected: 60, .painted: 30, .quiet: 10],
                                              line: "Calmest for city, and the quickest", selected: true)
}

#Preview {
    VStack(spacing: 16) {
        RouteCard(model: .sampleBest)
        RouteCard(model: .sampleFastest)
        RouteCard(model: .sampleSingle)
        RouteCardSkeleton()
    }
    .padding().background(Color.velix.canvas)
}
