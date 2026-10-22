import AppKit
import Foundation
import SwiftUI
import Testing
@testable import WedgeApp

@MainActor
@Suite struct SettingsLayoutTests {
    private func fittingHeight(status: LoginItemStatus, missingFolder: Bool, error: Bool) -> CGFloat {
        let name = "wedge-layout-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let service = FakeLoginItemService(status: status)
        let settings = SettingsModel(defaults: defaults, loginItems: service)
        if missingFolder { settings.setOutputFolder(URL(fileURLWithPath: "/nonexistent/wedge-\(UUID().uuidString)")) }
        if error {
            service.failNext()
            settings.setLaunchAtLogin(true)
        }
        let host = NSHostingController(rootView: SettingsView(settings: settings))
        host.sizingOptions = [.preferredContentSize]
        host.view.layoutSubtreeIfNeeded()
        return host.view.fittingSize.height
    }

    @Test func contentSizeGrowsWhenNotesAppear() {
        let plain = fittingHeight(status: .disabled, missingFolder: false, error: false)
        let busy = fittingHeight(status: .requiresApproval, missingFolder: true, error: true)
        #expect(plain > 100)
        #expect(busy > plain + 60)
    }
}
