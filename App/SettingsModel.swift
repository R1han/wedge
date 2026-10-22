import Foundation
import WedgeCore

@MainActor
final class SettingsModel: ObservableObject {
    static let shared = SettingsModel()

    static let defaultFormatKey = "defaultTargetFormat"
    static let outputFolderKey = "outputFolderPath"

    @Published private(set) var defaultFormat: FileFormat?
    /// nil means "next to originals".
    @Published private(set) var outputFolder: URL?
    @Published private(set) var launchAtLogin: LoginItemStatus
    @Published private(set) var launchAtLoginError: String?

    private let defaults: UserDefaults
    private let loginItems: LoginItemService
    private let fileManager: FileManager

    init(
        defaults: UserDefaults = .standard,
        loginItems: LoginItemService = SMLoginItemService(),
        fileManager: FileManager = .default
    ) {
        self.defaults = defaults
        self.loginItems = loginItems
        self.fileManager = fileManager
        defaultFormat = defaults.string(forKey: Self.defaultFormatKey).flatMap { id in
            FileFormat.known.first { $0.id == id }
        }
        outputFolder = defaults.string(forKey: Self.outputFolderKey).map { URL(fileURLWithPath: $0, isDirectory: true) }
        launchAtLogin = loginItems.status
    }

    func setDefaultFormat(_ format: FileFormat?) {
        defaultFormat = format
        defaults.set(format?.id, forKey: Self.defaultFormatKey)
    }

    func setOutputFolder(_ url: URL?) {
        outputFolder = url
        defaults.set(url?.path, forKey: Self.outputFolderKey)
    }

    /// The saved default when this batch can be converted to it; otherwise nil.
    func preferredTarget(among available: [FileFormat]) -> FileFormat? {
        defaultFormat.flatMap { available.contains($0) ? $0 : nil }
    }

    /// Resolves the saved folder: the folder to use (nil means next to the originals) and, when the
    /// folder had to be dropped, a note saying why.
    func resolveOutputFolder() -> (url: URL?, note: String?) {
        outputFolder.map(resolveOutputFolder) ?? (nil, nil)
    }

    /// Same rule for a folder chosen in the shelf for one session.
    func resolveOutputFolder(_ folder: URL) -> (url: URL?, note: String?) {
        let name = "\u{201C}\(folder.lastPathComponent)\u{201D}"
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return (nil, "The folder \(name) no longer exists. Files are saved next to the originals.")
        }
        guard fileManager.isWritableFile(atPath: folder.path) else {
            return (nil, "The folder \(name) is not writable. Files are saved next to the originals.")
        }
        return (folder, nil)
    }

    /// The status describes the system, so it replaces any message about an earlier attempt.
    func refreshLaunchAtLogin() {
        launchAtLogin = loginItems.status
        launchAtLoginError = nil
    }

    /// Applies the request, then shows what the system actually reports. A failure is published, never swallowed.
    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try loginItems.setEnabled(enabled)
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = "Couldn\u{2019}t turn Launch at Login \(enabled ? "on" : "off"): \(error.localizedDescription)"
        }
        launchAtLogin = loginItems.status
        if Self.satisfies(launchAtLogin, enabled: enabled) { launchAtLoginError = nil }
    }

    /// Whether the system status is already what the user asked for (so a thrown error was a race, not a failure).
    private static func satisfies(_ status: LoginItemStatus, enabled: Bool) -> Bool {
        switch status {
        case .enabled, .requiresApproval: enabled
        case .disabled, .notFound: !enabled
        }
    }

    func openLoginItemsSettings() {
        loginItems.openSystemSettings()
    }
}
