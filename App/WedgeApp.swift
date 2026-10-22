import SwiftUI

@main
struct WedgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var tools = ToolStatusModel()

    var body: some Scene {
        MenuBarExtra("Wedge", systemImage: "arrow.triangle.2.circlepath") {
            MenuBarContent(tools: tools)
        }
    }
}
