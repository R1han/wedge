import Foundation
import Testing
import WedgeCore
@testable import WedgeApp

@MainActor
@Suite struct SettingsModelTests {
    private let jpeg = FileFormat.format(forExtension: "jpg")!
    private let png = FileFormat.format(forExtension: "png")!
    private let webp = FileFormat.format(forExtension: "webp")!

    private func makeDefaults() -> UserDefaults {
        let name = "wedge-settings-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func makeModel(
        defaults: UserDefaults? = nil,
        service: FakeLoginItemService = FakeLoginItemService()
    ) -> SettingsModel {
        SettingsModel(defaults: defaults ?? makeDefaults(), loginItems: service)
    }

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("wedge-settings-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: Launch at login

    @Test func enablingReflectsServiceStatus() {
        let service = FakeLoginItemService()
        let model = makeModel(service: service)
        #expect(model.launchAtLogin == .disabled)
        model.setLaunchAtLogin(true)
        #expect(model.launchAtLogin == .enabled)
        #expect(model.launchAtLoginError == nil)
        model.setLaunchAtLogin(false)
        #expect(model.launchAtLogin == .disabled)
    }

    @Test func thrownErrorSurfacesAsMessageAndStatusIsUnchanged() {
        let service = FakeLoginItemService()
        let model = makeModel(service: service)
        service.failNext()
        model.setLaunchAtLogin(true)
        #expect(model.launchAtLogin == .disabled)
        let message = model.launchAtLoginError
        #expect(message?.contains("Operation not permitted") == true)
        #expect(message?.contains("on") == true)
    }

    @Test func successClearsEarlierError() {
        let service = FakeLoginItemService()
        let model = makeModel(service: service)
        service.failNext()
        model.setLaunchAtLogin(true)
        #expect(model.launchAtLoginError != nil)
        model.setLaunchAtLogin(true)
        #expect(model.launchAtLoginError == nil)
        #expect(model.launchAtLogin == .enabled)
    }

    @Test func errorIsDroppedWhenTheStatusAlreadyMatchesTheRequest() {
        let service = FakeLoginItemService()
        let model = makeModel(service: service)
        service.failNext(statusBecomes: .enabled)
        model.setLaunchAtLogin(true)
        #expect(model.launchAtLogin == .enabled)
        #expect(model.launchAtLoginError == nil)
    }

    @Test func errorIsKeptWhenTheStatusStillDiffers() {
        let service = FakeLoginItemService()
        let model = makeModel(service: service)
        service.failNext(statusBecomes: .disabled)
        model.setLaunchAtLogin(true)
        #expect(model.launchAtLoginError != nil)
    }

    @Test func refreshClearsAStaleError() {
        let service = FakeLoginItemService()
        let model = makeModel(service: service)
        service.failNext()
        model.setLaunchAtLogin(true)
        #expect(model.launchAtLoginError != nil)
        model.refreshLaunchAtLogin()
        #expect(model.launchAtLoginError == nil)
    }

    @Test func enablingWhilePendingApprovalShowsNoFalseError() {
        let service = FakeLoginItemService(status: .requiresApproval)
        let model = makeModel(service: service)
        model.setLaunchAtLogin(true)
        #expect(model.launchAtLogin == .requiresApproval)
        #expect(model.launchAtLoginError == nil)
    }

    @Test func notFoundKeepsEnablingPossibleAndSurfacesTheRealError() {
        let service = FakeLoginItemService(status: .notFound)
        let model = makeModel(service: service)
        #expect(model.launchAtLogin == .notFound)
        service.failNext()
        model.setLaunchAtLogin(true)
        #expect(model.launchAtLogin == .notFound)
        #expect(model.launchAtLoginError?.contains("Operation not permitted") == true)
        model.setLaunchAtLogin(true)
        #expect(model.launchAtLogin == .enabled)
    }

    @Test func statusIsReReadAfterSetNotAssumed() {
        let service = FakeLoginItemService()
        service.enableResult(.requiresApproval)
        let model = makeModel(service: service)
        model.setLaunchAtLogin(true)
        #expect(model.launchAtLogin == .requiresApproval)
    }

    @Test func failedDisableKeepsEnabledStatus() {
        let service = FakeLoginItemService(status: .enabled)
        let model = makeModel(service: service)
        #expect(model.launchAtLogin == .enabled)
        service.failNext()
        model.setLaunchAtLogin(false)
        #expect(model.launchAtLogin == .enabled)
        #expect(model.launchAtLoginError?.contains("off") == true)
    }

    @Test func refreshPicksUpChangesMadeOutsideTheApp() throws {
        let service = FakeLoginItemService()
        let model = makeModel(service: service)
        #expect(model.launchAtLogin == .disabled)
        try service.setEnabled(true)
        model.refreshLaunchAtLogin()
        #expect(model.launchAtLogin == .enabled)
    }

    @Test func approvalButtonOpensSystemSettings() {
        let service = FakeLoginItemService(status: .requiresApproval)
        let model = makeModel(service: service)
        model.openLoginItemsSettings()
        #expect(service.openedSettings == 1)
    }

    // MARK: Persistence

    @Test func defaultsRoundTripThroughUserDefaults() throws {
        let defaults = makeDefaults()
        let folder = try makeTempDir()
        let first = makeModel(defaults: defaults)
        #expect(first.defaultFormat == nil)
        #expect(first.outputFolder == nil)
        first.setDefaultFormat(webp)
        first.setOutputFolder(folder)

        let second = makeModel(defaults: defaults)
        #expect(second.defaultFormat == webp)
        #expect(second.outputFolder?.path == folder.path)

        second.setDefaultFormat(nil)
        second.setOutputFolder(nil)
        let third = makeModel(defaults: defaults)
        #expect(third.defaultFormat == nil)
        #expect(third.outputFolder == nil)
    }

    @Test func unknownSavedFormatIsIgnored() {
        let defaults = makeDefaults()
        defaults.set("not-a-format", forKey: SettingsModel.defaultFormatKey)
        #expect(makeModel(defaults: defaults).defaultFormat == nil)
    }

    // MARK: Output folder resolution

    @Test func existingFolderIsUsed() throws {
        let folder = try makeTempDir()
        let model = makeModel()
        model.setOutputFolder(folder)
        let resolved = model.resolveOutputFolder()
        #expect(resolved.url?.path == folder.path)
        #expect(resolved.note == nil)
    }

    @Test func missingFolderFallsBackToNextToOriginalsWithNote() throws {
        let folder = try makeTempDir()
        let model = makeModel()
        model.setOutputFolder(folder)
        try FileManager.default.removeItem(at: folder)
        let resolved = model.resolveOutputFolder()
        #expect(resolved.url == nil)
        #expect(resolved.note?.contains(folder.lastPathComponent) == true)
    }

    @Test func aFileInPlaceOfTheFolderIsNotUsed() throws {
        let dir = try makeTempDir()
        let file = dir.appendingPathComponent("not-a-folder")
        try Data().write(to: file)
        let model = makeModel()
        model.setOutputFolder(file)
        let resolved = model.resolveOutputFolder()
        #expect(resolved.url == nil)
        #expect(resolved.note != nil)
    }

    @Test func aFolderThatIsNotWritableFallsBackWithNote() throws {
        let folder = try makeTempDir()
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path) }
        let model = makeModel()
        model.setOutputFolder(folder)
        let resolved = model.resolveOutputFolder()
        #expect(resolved.url == nil)
        #expect(resolved.note?.contains("writable") == true)
    }

    @Test func noFolderMeansNextToOriginalsWithoutNote() {
        let resolved = makeModel().resolveOutputFolder()
        #expect(resolved.url == nil)
        #expect(resolved.note == nil)
    }

    @Test func aSessionFolderIsResolvedTheSameWay() throws {
        let folder = try makeTempDir()
        let model = makeModel()
        #expect(model.resolveOutputFolder(folder).url?.path == folder.path)
        try FileManager.default.removeItem(at: folder)
        let resolved = model.resolveOutputFolder(folder)
        #expect(resolved.url == nil)
        #expect(resolved.note != nil)
    }

    // MARK: Shelf initial selection

    @Test func preferredTargetHonoursDefaultWhenAvailable() {
        let model = makeModel()
        model.setDefaultFormat(jpeg)
        #expect(model.preferredTarget(among: [png, jpeg]) == jpeg)
    }

    @Test func preferredTargetIgnoresDefaultWhenNotAvailable() {
        let model = makeModel()
        model.setDefaultFormat(webp)
        #expect(model.preferredTarget(among: [png, jpeg]) == nil)
        #expect(makeModel().preferredTarget(among: [png, jpeg]) == nil)
    }

    @Test func readingThePreferredTargetDoesNotChangeSavedDefaults() {
        let defaults = makeDefaults()
        let model = makeModel(defaults: defaults)
        model.setDefaultFormat(png)
        _ = model.preferredTarget(among: [png, jpeg])
        #expect(makeModel(defaults: defaults).defaultFormat == png)
    }
}
