import Foundation
import ServiceManagement
import Testing
@testable import WedgeApp

final class FakeLoginItemService: LoginItemService, @unchecked Sendable {
    struct Failure: LocalizedError {
        var errorDescription: String? { "Operation not permitted" }
    }

    private let lock = NSLock()
    private var _status: LoginItemStatus
    private var _failure: Error?
    private var _opened = 0
    /// What the system reports after an enable request, instead of .enabled.
    private var _enableResult: LoginItemStatus = .enabled

    init(status: LoginItemStatus = .disabled) { _status = status }

    var status: LoginItemStatus { lock.withLock { _status } }
    var openedSettings: Int { lock.withLock { _opened } }
    func failNext(with error: Error = Failure()) { lock.withLock { _failure = error } }
    func enableResult(_ status: LoginItemStatus) { lock.withLock { _enableResult = status } }

    func setEnabled(_ enabled: Bool) throws {
        try lock.withLock {
            if let error = _failure {
                _failure = nil
                throw error
            }
            _status = enabled ? _enableResult : .disabled
        }
    }

    func openSystemSettings() { lock.withLock { _opened += 1 } }
}

@Suite struct LoginItemServiceTests {
    @Test func fakeToggles() throws {
        let service = FakeLoginItemService()
        try service.setEnabled(true)
        #expect(service.status == .enabled)
        try service.setEnabled(false)
        #expect(service.status == .disabled)
    }

    @Test func fakeThrowsOnceAndKeepsStatus() {
        let service = FakeLoginItemService()
        service.failNext()
        #expect(throws: FakeLoginItemService.Failure.self) { try service.setEnabled(true) }
        #expect(service.status == .disabled)
    }

    @Test func statusMappingCoversEverySystemStatus() {
        #expect(SMLoginItemService.map(.enabled) == .enabled)
        #expect(SMLoginItemService.map(.notRegistered) == .disabled)
        #expect(SMLoginItemService.map(.requiresApproval) == .requiresApproval)
        guard case .unavailable(let reason) = SMLoginItemService.map(.notFound) else {
            Issue.record("notFound should map to unavailable")
            return
        }
        #expect(!reason.isEmpty)
    }
}
