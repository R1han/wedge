import AppKit
import Foundation
import Testing
@testable import WedgeApp

@Suite struct LaunchPolicyTests {
    private func makeDefaults() -> UserDefaults {
        let name = "wedge-launch-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func firstRunOpensShelfOnce() {
        let policy = LaunchPolicy(defaults: makeDefaults())
        #expect(policy.shouldOpenShelfOnLaunch())
        #expect(!policy.shouldOpenShelfOnLaunch())
    }

    @Test func laterLaunchesDoNotOpenShelf() {
        let defaults = makeDefaults()
        #expect(LaunchPolicy(defaults: defaults).shouldOpenShelfOnLaunch())
        #expect(!LaunchPolicy(defaults: defaults).shouldOpenShelfOnLaunch())
    }

    @Test func flagUsesHasLaunchedBeforeKey() {
        let defaults = makeDefaults()
        _ = LaunchPolicy(defaults: defaults).shouldOpenShelfOnLaunch()
        #expect(defaults.bool(forKey: "hasLaunchedBefore"))
    }
}

@Suite struct SingleInstanceTests {
    private func lockURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("wedge-lock-\(UUID().uuidString)")
            .appendingPathComponent("instance.lock")
    }

    @Test func firstAcquireSucceedsAndCreatesDirectory() {
        let url = lockURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        #expect(InstanceLock.acquire(at: url) != nil)
    }

    @Test func secondAcquireFailsWhileHeld() {
        let url = lockURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let first = InstanceLock.acquire(at: url)
        #expect(first != nil)
        #expect(InstanceLock.acquire(at: url) == nil)
        withExtendedLifetime(first) {}
    }

    @Test func acquireSucceedsAfterRelease() {
        let url = lockURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        var first = InstanceLock.acquire(at: url)
        #expect(first != nil)
        first = nil
        #expect(InstanceLock.acquire(at: url) != nil)
    }

    @Test func notificationNamesAreScopedToBundleId() {
        #expect(SingleInstance.showShelfNotification(bundleID: "com.r1han.wedge").rawValue == "com.r1han.wedge.showShelf")
        #expect(SingleInstance.ackNotification(bundleID: "com.r1han.wedge").rawValue == "com.r1han.wedge.showShelfAck")
    }

    @Test func testHostIsDetectedUnderXCTest() {
        #expect(RuntimeEnvironment.isTestHost)
    }
}

@MainActor @Suite struct MenuIdentityTests {
    @Test func recognisesOurMenuByItsTitles() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Open Shelf", action: nil, keyEquivalent: "")
        #expect(MenuBarContent.isWedgeMenu(menu))
        #expect(!MenuBarContent.isWedgeMenu(NSMenu()))
    }
}
