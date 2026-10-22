import Foundation
import Testing
import WedgeCore

@Suite struct AppSmokeTests {
    @Test func hostBundleIsMenuBarOnlyApp() {
        let info = Bundle.main.infoDictionary
        #expect(info?["CFBundleName"] as? String == "Wedge")
        #expect(info?["LSUIElement"] as? Bool == true)
    }

    @Test func coreLibraryIsLinked() {
        #expect(!Wedge.defaultRegistry().pairs().isEmpty)
    }
}
