import Testing
@testable import Velix

/// The app carries the licence text of everything it ships (tools/licenses/licenses.py → Licenses.json).
@Suite struct LicencesTests {
    @Test func everyShippedComponentHasItsText() {
        let names = Set(OpenSourceLicencesView.entries.map(\.name))
        for n in ["MapLibre Native", "Ferrostar", "Valhalla", "Atkinson Hyperlegible", "Lucide icons"] {
            #expect(names.contains(n))
        }
        #expect(OpenSourceLicencesView.entries.allSatisfy { $0.text.count > 300 })
    }
}
