import Foundation
import Testing
@testable import Velix

@MainActor
struct RouteOptionsTests {
    @Test func differenceLinesGetTheirBoldLead() {
        #expect(DifferenceCopy.markup("+5 min · avoids 300 m cobbles") == "**+5 min** · avoids 300 m cobbles")
        #expect(DifferenceCopy.markup("5 min quicker · busy Corso Buenos Aires") == "**5 min quicker** · busy Corso Buenos Aires")
        #expect(DifferenceCopy.markup("Fastest is only 30 s quicker, with rails. So there’s one route.")
                == "Fastest is **only 30 s quicker**, with rails. So there’s one route.")
        #expect(DifferenceCopy.markup("Fastest takes the same way. So there’s one route.")
                == "Fastest takes the same way. So there’s one route.")
    }

    @Test func cardsFromOptions() {
        let m = RouteOptionsModel(destination: AppSamples.politecnico, state: .options(AppSamples.options()))
        let cards = m.cards
        #expect(cards.map(\.name) == ["Calmest for city", "Fastest"])
        #expect(cards[0].minutes == 23 && cards[0].distance == "5.4 km" && cards[0].selected)
        #expect(cards[0].line == "**+5 min** · avoids 300 m cobbles and busy Corso Buenos Aires")
        m.fastestSelected = true
        #expect(m.cards[1].selected && !m.cards[0].selected)
        #expect(m.chosen?.seconds == Double(18 * 60))
    }

    @Test func singleCardHasNoFastest() {
        let m = RouteOptionsModel(destination: AppSamples.politecnico, state: .options(AppSamples.options(single: true)))
        #expect(m.cards.map(\.name) == ["Best and fastest"])
        m.fastestSelected = true
        #expect(m.chosen?.seconds == Double(13 * 60))   // nothing else to ride
    }

    @Test func whyThisRouteRows() {
        let m = RouteOptionsModel(destination: AppSamples.politecnico, state: .options(AppSamples.options()))
        let rows = m.hazardRows
        #expect(rows.map(\.type) == [.cobbles, .steps])           // tram rails aren't listed (29 Oct)
        #expect(rows[1].count == 1 && rows[1].subtitle == "Piazza Oberdan")
        #expect(rows[0].amount == "70 m")
        #expect(m.avoidedRows.map(\.name) == ["Viale Piave", "Via Morgagni"])
    }

    @Test func blockedCopy() {
        let (why, rule) = RouteOptionsModel.blockedMessage(rule: .noCobbles, rideType: .cargo, destination: "Piazza del Duomo")
        #expect(why == "Every street into Piazza del Duomo has cobbles.")
        #expect(rule == "**No cobbles** is on for Cargo / kids.")
    }

    @Test func liveActivityContentBeforeTheFirstFix() {
        let s = RideSession.content(nil, destination: AppSamples.politecnico, fallbackMeters: 2400)
        #expect(s.distanceLeft == "2.4 km")
        #expect(s.street == "Politecnico")
        #expect(RideSession.distance(184) == "180 m")
        #expect(RideSession.distance(1240) == "1.2 km")
    }
}
