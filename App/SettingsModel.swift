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

    /// The saved folder if it still exists, else nil (next to the originals).
    var resolvedOutputDirectory: URL? {
        outputFolder.flatMap { directoryExists($0) ? $0 : nil }
    }

    /// Explains why the saved folder is not being used; nil when it is fine or none is set.
    var outputFolderNote: String? {
        guard let folder = outputFolder, !directoryExists(folder) else { return nil }
        return "The folder \u{201C}\(folder.lastPathComponent)\u{201D} no longer exists. Files are saved next to the originals."
    }

    func directoryExists(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    func refreshLaunchAtLogin() {
        launchAtLogin = loginItems.status
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
    }

    func openLoginItemsSettings() {
        loginItems.openSystemSettings()
    }
}
