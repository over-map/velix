import FerrostarCore
import MapLibre
import Testing
import Valhalla

/// Proves the pinned SPM dependencies link into the test host. Real use starts in M1.
struct DependencyLinkTests {
    @Test func dependenciesLink() {
        let linked: [Any.Type] = [MLNMapView.self, FerrostarCore.self, Valhalla.self]
        #expect(linked.count == 3)
    }
}
