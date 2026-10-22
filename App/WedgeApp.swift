import SwiftUI

@main
struct WedgeApp: App {
    var body: some Scene {
        MenuBarExtra("Wedge", systemImage: "arrow.triangle.2.circlepath") {
            Button("Quit Wedge") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}
