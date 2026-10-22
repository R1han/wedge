import SwiftUI

@main
struct WedgeApp: App {
    var body: some Scene {
        MenuBarExtra("Wedge", systemImage: "arrow.triangle.2.circlepath") {
            Button("Open Shelf") {
                ShelfWindowController.shared.show()
            }
            Button("Quit Wedge") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}
