import Foundation
import Testing
import WedgeCore
@testable import WedgeApp

@Suite struct ToolStatusTests {
    private let ls = ExternalTool(name: "ls", installHint: "brew install ls")
    private let nonsense = ExternalTool(name: "definitely-not-a-real-tool-xyz", installHint: "brew install nonsense")

    private func lookup(_ name: String) -> URL? {
        name == "ls" ? URL(fileURLWithPath: "/bin/ls") : nil
    }

    @Test func reportsFoundAndMissing() {
        let statuses = ToolStatus.all(tools: [ls, nonsense], lookup: lookup)
        #expect(statuses.map(\.isFound) == [true, false])
    }

    @Test func foundTitleHasNoHint() {
        let status = ToolStatus.all(tools: [ls], lookup: lookup)[0]
        #expect(status.menuTitle == "ls: found")
    }

    @Test func missingTitleCarriesInstallHint() {
        let status = ToolStatus.all(tools: [nonsense], lookup: lookup)[0]
        #expect(status.menuTitle == "definitely-not-a-real-tool-xyz: not installed \u{2014} brew install nonsense")
    }

    @Test func defaultsCoverCoreTools() {
        let statuses = ToolStatus.all(lookup: { _ in nil })
        #expect(statuses.map(\.tool) == ExternalTool.all)
        #expect(statuses.map(\.menuTitle) == [
            "pandoc: not installed \u{2014} brew install pandoc",
            "ffmpeg: not installed \u{2014} brew install ffmpeg",
        ])
    }

    @Test func defaultLookupResolvesRealTools() {
        #expect(ToolStatus.all(tools: [ExternalTool(name: "tar", installHint: "")])[0].isFound)
        #expect(!ToolStatus.all(tools: [nonsense])[0].isFound)
    }
}
