import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let handOffTimeout: TimeInterval = 2
    private static let repostInterval: TimeInterval = 0.25

    private var lock: InstanceLock?
    private var bundleID = ""
    private var handOffDone = false

    private var center: DistributedNotificationCenter { .default() }

    func applicationWillFinishLaunching(_ notification: Notification) {
        guard !RuntimeEnvironment.isTestHost,
              let bundleID = Bundle.main.bundleIdentifier,
              let lockURL = InstanceLock.defaultURL(bundleID: bundleID)
        else { return }
        self.bundleID = bundleID

        if let acquired = InstanceLock.acquire(at: lockURL) {
            lock = acquired
            center.addObserver(
                self, selector: #selector(showShelfRequested),
                name: SingleInstance.showShelfNotification(bundleID: bundleID),
                object: nil, suspensionBehavior: .deliverImmediately
            )
        } else {
            handOffToRunningInstance()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard lock != nil, LaunchPolicy(defaults: .standard).shouldOpenShelfOnLaunch() else { return }
        ShelfWindowController.shared.show()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        ShelfWindowController.shared.show()
        return true
    }

    @objc private func showShelfRequested(_ notification: Notification) {
        ShelfWindowController.shared.show()
        center.postNotificationName(
            SingleInstance.ackNotification(bundleID: bundleID), object: nil, userInfo: nil, deliverImmediately: true
        )
    }

    /// Asks the instance holding the lock to show its shelf, then quits on its ack or after the timeout.
    private func handOffToRunningInstance() {
        let holder = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        holder?.activate()

        center.addObserver(
            self, selector: #selector(ackReceived),
            name: SingleInstance.ackNotification(bundleID: bundleID),
            object: nil, suspensionBehavior: .deliverImmediately
        )
        postShowShelf(until: Date().addingTimeInterval(Self.handOffTimeout))
    }

    /// Re-posts until acked, in case the holder had not registered its observer yet.
    private func postShowShelf(until deadline: Date) {
        guard !handOffDone else { return }
        guard Date() < deadline else { return finishHandOff() }
        center.postNotificationName(
            SingleInstance.showShelfNotification(bundleID: bundleID), object: nil, userInfo: nil, deliverImmediately: true
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.repostInterval) { [weak self] in
            MainActor.assumeIsolated { self?.postShowShelf(until: deadline) }
        }
    }

    @objc private func ackReceived(_ notification: Notification) {
        finishHandOff()
    }

    private func finishHandOff() {
        guard !handOffDone else { return }
        handOffDone = true
        NSApp.terminate(nil)
    }
}
