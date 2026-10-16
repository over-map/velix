import Foundation
import Testing
@testable import TokenGenCore

struct TokenGenTests {
    let tokens = Data("""
    {"meta": {"version": "test"},
     "color": {"accent": {"light": "#DBF227", "dark": "#DBF227", "use": "Your route"},
               "routeAlt": {"light": "#6A808B", "dark": "#9AA6AA"},
               "transitMetroRed": {"light": "#C8102E", "dark": "#C8102E", "alt": "#94101F", "ink": "#FFFFFF", "altInk": "#FFFFFF"}},
     "palette": {"navy": "#042940", "note": "text"},
     "font": {"body": {"family": "Atkinson Hyperlegible", "weight": 400, "size": 17, "lineHeight": 24, "tracking": "0", "tabularNumbers": false, "dynamicType": "full range"},
              "ridingBigNumber": {"family": "Familjen Grotesk", "weight": 700, "size": 56, "lineHeight": 56, "tracking": "-0.02em", "tabularNumbers": true, "dynamicType": "capped at xxLarge (+35%)"}},
     "spacing": {"xs": {"value": 8}, "m": {"value": 16}},
     "radius": {"card": {"value": 16}},
     "touchTarget": {"min": 44, "riding": 60},
     "elevation": {"e1": {"light": {"y": 2, "blur": 6, "color": "#021624", "opacity": 0.15}, "dark": {"border": "#1F4862"}}},
     "motion": {"press": {"durationMs": 120, "curve": "easeOut", "use": "Scale 0.96", "reduceMotion": "Opacity only"}}}
    """.utf8)

    @Test func generatesColorsWithBothAppearances() throws {
        let out = try TokenGen.generate(tokens: tokens, overrides: nil)
        let accent = try #require(out.assets["VelixColors/velixAccent.colorset/Contents.json"])
        #expect(accent.contains("\"red\" : \"0.859\""))
        #expect(accent.contains("\"value\" : \"dark\""))
        #expect(out.swift["Color+Velix.swift"]!.contains("static let accent = Color(\"velixAccent\", bundle: .main)"))
        #expect(out.assets["VelixColors/velixTransitMetroRedAlt.colorset/Contents.json"] != nil)
        #expect(out.assets["VelixColors/velixPaletteNavy.colorset/Contents.json"] != nil)
        #expect(out.assets.keys.allSatisfy { !$0.contains("Note") })
    }

    @Test func overridesWinAndDocumentationKeysAreIgnored() throws {
        let overrides = Data(##"{"_note": "x", "color": {"routeAlt": {"light": "#2F4FD8", "dark": "#8EA2FF", "reason": "why"}}}"##.utf8)
        let out = try TokenGen.generate(tokens: tokens, overrides: overrides)
        let alt = try #require(out.assets["VelixColors/velixRouteAlt.colorset/Contents.json"])
        #expect(alt.contains("\"red\" : \"0.184\""))  // 0x2F
        #expect(alt.contains("\"blue\" : \"1.000\""))  // 0xFF in dark
    }

    @Test func fontsMapToBundledPostScriptNames() throws {
        let swift = try TokenGen.generate(tokens: tokens, overrides: nil).swift["Font+Velix.swift"]!
        #expect(swift.contains("postScriptName: \"AtkinsonHyperlegible-Regular\", size: 17, lineHeight: 24"))
        #expect(swift.contains("postScriptName: \"FamiljenGroteskRoman-Bold\", size: 56, lineHeight: 56, trackingEm: -0.02, tabularNumbers: true, riding: true"))
    }

    @Test func metricsAreSortedByValue() throws {
        let out = try TokenGen.generate(tokens: tokens, overrides: nil)
        let swift = out.swift["Metrics+Velix.swift"]!
        let xs = try #require(swift.range(of: "xs: CGFloat = 8")).lowerBound
        let m = try #require(swift.range(of: "m: CGFloat = 16")).lowerBound
        #expect(xs < m)
        #expect(swift.contains("static let riding: CGFloat = 60"))
        #expect(swift.contains("VelixShadow(y: 2, blur: 6, opacity: 0.15)"))
        #expect(swift.contains("border: Color(\"velixElevationE1DarkBorder\", bundle: .main)"))
        #expect(out.assets["VelixColors/velixElevationE1DarkBorder.colorset/Contents.json"] != nil)
    }

    @Test func badHexFails() {
        let bad = Data(##"{"color": {"x": {"light": "#12", "dark": "#123456"}}, "font": {}, "spacing": {}, "radius": {}, "touchTarget": {}}"##.utf8)
        #expect(throws: TokenGen.Failure.self) { try TokenGen.generate(tokens: bad, overrides: nil) }
    }
}
