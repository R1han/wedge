import Foundation
import Testing
@testable import WedgeCore

@Suite struct ExternalToolTests {
    @Test func test_all_listsPandocAndFfmpegWithBrewHints() {
        #expect(ExternalTool.all.map(\.name) == ["pandoc", "ffmpeg"])
        #expect(ExternalTool.all.map(\.installHint) == ["brew install pandoc", "brew install ffmpeg"])
    }
}

@Suite struct ToolLocatorTests {
    @Test func test_path_findsAlwaysPresentTool() {
        let url = ToolLocator.shared.path(for: "tar")
        #expect(url != nil)
        if let url { #expect(FileManager.default.isExecutableFile(atPath: url.path)) }
    }

    @Test func test_path_returnsNilForUnknownTool() {
        #expect(ToolLocator.shared.path(for: "definitely-not-a-real-tool-xyz") == nil)
    }

    @Test func test_path_returnsNilForEmptyName() {
        #expect(ToolLocator.shared.path(for: "") == nil)
    }
}
