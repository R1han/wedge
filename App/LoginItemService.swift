import Foundation
import ServiceManagement

enum LoginItemStatus: Equatable, Sendable {
    case enabled
    case disabled
    /// Registered, but the user has to allow it in System Settings, Login Items.
    case requiresApproval
    case unavailable(String)
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
            if service.status != .enabled { try service.register() }
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
        case .notFound: .unavailable("Wedge could not be found as a login item. Move it to the Applications folder and reopen it.")
        @unknown default: .unavailable("Launch at Login is not available on this system.")
        }
    }
}
