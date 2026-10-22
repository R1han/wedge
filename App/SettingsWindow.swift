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
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeWindow() -> NSWindow {
        let window = SettingsNSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 340),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Wedge Settings"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SettingsView(settings: .shared))
        window.center()
        return window
    }
}
