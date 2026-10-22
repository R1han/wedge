import Foundation
import ServiceManagement

enum LoginItemStatus: Equatable, Sendable {
    case enabled
    case disabled
    /// Registered, but the user has to allow it in System Settings, Login Items.
    case requiresApproval
    /// The system cannot find the login item (often a build outside /Applications). Enabling is still attempted.
    case notFound
}

protocol LoginItemService: Sendable {
    var status: LoginItemStatus { get }
    func setEnabled(_ enabled: Bool) throws
    func openSystemSettings()
}

struct SMLoginItemService: LoginItemService {
    var status: LoginItemStatus { Self.map(SMAppService.mainApp.status) }

    func setEnabled(_ enabled: Bool) throws {
        let service = SMAppService.mainApp
        if enabled {
            if service.status != .enabled && service.status != .requiresApproval { try service.register() }
        } else if service.status == .enabled || service.status == .requiresApproval {
            try service.unregister()
        }
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    static func map(_ status: SMAppService.Status) -> LoginItemStatus {
        switch status {
        case .enabled: .enabled
        case .notRegistered: .disabled
        case .requiresApproval: .requiresApproval
        case .notFound: .notFound
        @unknown default: .disabled
        }
    }
}
