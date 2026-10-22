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
    @Test func runsNormallyWhenAlone() {
        #expect(SingleInstance.action(otherPids: []) == .runNormally)
    }

    @Test func defersToTheFirstOtherInstance() {
        #expect(SingleInstance.action(otherPids: [4242, 99]) == .deferTo(4242))
    }

    @Test func notificationNameIsScopedToBundleId() {
        #expect(SingleInstance.showShelfNotification(bundleID: "com.r1han.wedge").rawValue == "com.r1han.wedge.showShelf")
    }
}
