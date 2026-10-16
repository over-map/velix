import Testing
import UIKit
@testable import Velix

struct FontRegistrationTests {
    static let names = Set([VelixType.display, .title1, .title2, .headline, .body, .bodyBold, .callout, .footnote, .caption,
                             .numberL, .numberM, .ridingBigNumber, .ridingNumber, .ridingStreet, .ridingLabel].map(\.postScriptName))
        .union(["FamiljenGroteskRoman-Medium", "FamiljenGroteskRoman-SemiBold"])

    @Test(arguments: Array(names).sorted())
    func bundledFontLoads(_ postScriptName: String) {
        #expect(UIFont(name: postScriptName, size: 17) != nil, "\(postScriptName) is not registered; check UIAppFonts in project.yml")
    }
}
