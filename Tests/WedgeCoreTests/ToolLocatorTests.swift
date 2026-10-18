import Foundation
import Testing
@testable import WedgeCore

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
