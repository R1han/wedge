import AppKit

extension NSApplication {
    /// Brings the app to the front, using the cooperative API where the system has it.
    func bringToFront() {
        if #available(macOS 14, *) {
            activate()
        } else {
            activate(ignoringOtherApps: true)
        }
    }
}
