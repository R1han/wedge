import SwiftUI

@main
struct WedgeApp: App {
    var body: some Scene {
        MenuBarExtra("Wedge", systemImage: "arrow.triangle.2.circlepath") {
            Button("Open Shelf") {
                ShelfWindowController.shared.show()
            }
            Button("Settings\u{2026}") {
                SettingsWindowController.shared.show()
            }
            .keyboardShortcut(",")
            Button("Quit Wedge") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}
