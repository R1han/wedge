import AppKit
import SwiftUI

private final class ShelfPanel: NSPanel {
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
final class ShelfWindowController {
    static let shared = ShelfWindowController()

    private static let autosaveName = "WedgeShelf"
    private let model = ConversionModel()
    private var panel: NSPanel?

    /// Creates the shelf on first use; afterwards brings the existing panel to the front.
    func show() {
        let panel = panel ?? makePanel()
        self.panel = panel
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makePanel() -> NSPanel {
        let panel = ShelfPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 420),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Wedge"
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: ShelfView(model: model, settings: .shared))
        if !panel.setFrameUsingName(Self.autosaveName) { panel.center() }
        panel.setFrameAutosaveName(Self.autosaveName)
        return panel
    }
}
