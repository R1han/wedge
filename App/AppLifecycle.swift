import Foundation

/// Opens the shelf automatically on the very first launch only.
struct LaunchPolicy {
    private static let key = "hasLaunchedBefore"

    let defaults: UserDefaults

    /// True the first time it is asked (and records that), false afterwards.
    func shouldOpenShelfOnLaunch() -> Bool {
        guard !defaults.bool(forKey: Self.key) else { return false }
        defaults.set(true, forKey: Self.key)
        return true
    }
}

enum InstanceAction: Equatable {
    case runNormally
    case deferTo(pid_t)
}

enum SingleInstance {
    /// What a freshly launched instance should do, given the pids of other running copies of the app.
    static func action(otherPids: [pid_t]) -> InstanceAction {
        otherPids.first.map(InstanceAction.deferTo) ?? .runNormally
    }

    static func showShelfNotification(bundleID: String) -> Notification.Name {
        Notification.Name("\(bundleID).showShelf")
    }
}
