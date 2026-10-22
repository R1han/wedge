import SwiftUI

struct MenuBarContent: View {
    @ObservedObject var tools: ToolStatusModel

    var body: some View {
        Button("Open Shelf") {
            ShelfWindowController.shared.show()
        }
        .keyboardShortcut("o")
        Button("Settings\u{2026}") {
            SettingsWindowController.shared.show()
        }
        .keyboardShortcut(",")
        Divider()
        Section("Tools") {
            ForEach(tools.statuses, id: \.tool.name) { status in
                Text(status.menuTitle)
            }
        }
        Divider()
        Button("Quit Wedge") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
