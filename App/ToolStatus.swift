import AppKit
import WedgeCore

/// Whether one external tool the converters need can be found, shown in the menu.
struct ToolStatus: Equatable {
    let tool: ExternalTool
    let isFound: Bool

    var menuTitle: String {
        isFound ? "\(tool.name): found" : "\(tool.name): not installed \u{2014} \(tool.installHint)"
    }

    static func all(
        tools: [ExternalTool] = ExternalTool.all,
        lookup: (String) -> URL? = { ToolLocator.shared.path(for: $0) }
    ) -> [ToolStatus] {
        tools.map { ToolStatus(tool: $0, isFound: lookup($0.name) != nil) }
    }
}

/// Re-checks the tools (for the life of the app) each time a menu-bar menu opens, so installing one is picked up without a relaunch.
@MainActor
final class ToolStatusModel: ObservableObject {
    @Published private(set) var statuses = ToolStatus.all()

    init() {
        NotificationCenter.default.addObserver(
            forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func refresh() {
        let latest = ToolStatus.all()
        if latest != statuses { statuses = latest }
    }
}
