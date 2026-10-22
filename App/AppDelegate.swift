import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var showShelfObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
              let bundleID = Bundle.main.bundleIdentifier else { return }
        let name = SingleInstance.showShelfNotification(bundleID: bundleID)
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }

        if case .deferTo(let pid) = SingleInstance.action(otherPids: others.map(\.processIdentifier)) {
            others.first { $0.processIdentifier == pid }?.activate()
            DistributedNotificationCenter.default().postNotificationName(
                name, object: nil, userInfo: nil, deliverImmediately: true
            )
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { NSApp.terminate(nil) }
            return
        }

        showShelfObserver = DistributedNotificationCenter.default().addObserver(
            forName: name, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { ShelfWindowController.shared.show() }
        }
        if LaunchPolicy(defaults: .standard).shouldOpenShelfOnLaunch() {
            ShelfWindowController.shared.show()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        ShelfWindowController.shared.show()
        return true
    }
}
