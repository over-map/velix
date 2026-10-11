import Testing
import UIKit
@testable import Velix

struct FontRegistrationTests {
    @Test(arguments: Bootstrap.Font.postScriptNames)
    func bundledFontLoads(_ postScriptName: String) {
        #expect(UIFont(name: postScriptName, size: 17) != nil, "\(postScriptName) is not registered; check UIAppFonts in project.yml")
    }
}
