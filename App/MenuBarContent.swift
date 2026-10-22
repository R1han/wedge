import SwiftUI

struct MenuBarContent: View {
    @ObservedObject var tools: ToolStatusModel

    var body: some View {
        Button(Self.openShelfTitle) {
            ShelfWindowController.shared.show()
        }
        .keyboardShortcut("o")
        Button("Settings\u{2026}") {
            SettingsWindowController.shared.show()
        }
        .keyboardShortcut(",")
        Divider()
        Menu("Tools") {
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

    static let openShelfTitle = "Open Shelf"

    /// Whether a tracked menu is the menu-bar menu above, as opposed to some other popup.
    static func isWedgeMenu(_ menu: NSMenu) -> Bool {
        menu.items.contains { $0.title == openShelfTitle }
    }
}
