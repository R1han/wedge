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
    private var _statusAfterFailure: LoginItemStatus?
    private var _opened = 0
    /// What the system reports after an enable request, instead of .enabled.
    private var _enableResult: LoginItemStatus = .enabled

    init(status: LoginItemStatus = .disabled) { _status = status }

    var status: LoginItemStatus { lock.withLock { _status } }
    var openedSettings: Int { lock.withLock { _opened } }
    /// The next setEnabled throws; `statusBecomes` simulates the system having changed anyway (a race).
    func failNext(with error: Error = Failure(), statusBecomes: LoginItemStatus? = nil) {
        lock.withLock {
            _failure = error
            _statusAfterFailure = statusBecomes
        }
    }
    func enableResult(_ status: LoginItemStatus) { lock.withLock { _enableResult = status } }

    func setEnabled(_ enabled: Bool) throws {
        try lock.withLock {
            if let error = _failure {
                _failure = nil
                if let after = _statusAfterFailure { _status = after }
                _statusAfterFailure = nil
                throw error
            }
            if enabled, _status == .requiresApproval || _status == .enabled { return }
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

    @Test func fakeEnableWhilePendingApprovalIsANoOp() throws {
        let service = FakeLoginItemService(status: .requiresApproval)
        try service.setEnabled(true)
        #expect(service.status == .requiresApproval)
    }

    @Test func statusMappingCoversEverySystemStatus() {
        #expect(SMLoginItemService.map(.enabled) == .enabled)
        #expect(SMLoginItemService.map(.notRegistered) == .disabled)
        #expect(SMLoginItemService.map(.requiresApproval) == .requiresApproval)
        #expect(SMLoginItemService.map(.notFound) == .notFound)
    }
}
