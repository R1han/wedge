import AppKit
import SwiftUI

private final class SettingsNSWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers == "w" {
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    /// Creates the window on first use; afterwards brings the existing one to the front.
    func show() {
        let window = window ?? makeWindow()
        self.window = window
        SettingsModel.shared.refreshLaunchAtLogin()
        window.makeKeyAndOrderFront(nil)
        NSApp.bringToFront()
    }

    private func makeWindow() -> NSWindow {
        let content = NSHostingController(rootView: SettingsView(settings: .shared))
        content.sizingOptions = [.preferredContentSize]
        let window = SettingsNSWindow(contentViewController: content)
        window.styleMask = [.titled, .closable]
        window.title = "Wedge Settings"
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}
