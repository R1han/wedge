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

/// An exclusive lock held for the life of the process. The OS drops it on exit or crash, so it cannot go stale.
final class InstanceLock: @unchecked Sendable {
    private var descriptor: Int32

    private init(descriptor: Int32) { self.descriptor = descriptor }

    deinit { close(descriptor) }

    /// The lock, or nil when another process (or descriptor) already holds it or the file cannot be opened.
    static func acquire(at url: URL) -> InstanceLock? {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            return nil
        }
        let descriptor = open(url.path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { return nil }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            return nil
        }
        return InstanceLock(descriptor: descriptor)
    }

    static func defaultURL(bundleID: String) -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("instance.lock")
    }
}

enum SingleInstance {
    static func showShelfNotification(bundleID: String) -> Notification.Name {
        Notification.Name("\(bundleID).showShelf")
    }

    static func ackNotification(bundleID: String) -> Notification.Name {
        Notification.Name("\(bundleID).showShelfAck")
    }
}

enum RuntimeEnvironment {
    /// True when hosting unit tests; production never loads XCTest.
    static var isTestHost: Bool { NSClassFromString("XCTestCase") != nil }
}
