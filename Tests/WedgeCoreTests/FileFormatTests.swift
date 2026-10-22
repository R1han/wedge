import Testing
@testable import WedgeCore

@Suite struct FileFormatTests {
    @Test func test_formatForExtension_isCaseInsensitive() {
        #expect(FileFormat.format(forExtension: "PNG")?.id == "png")
    }

    @Test func test_unknownExtension_returnsNil() {
        #expect(FileFormat.format(forExtension: "notarealext") == nil)
    }

    @Test func test_known_includesHeicAndZip() {
        let ids = FileFormat.known.map(\.id)
        #expect(ids.contains("heic"))
        #expect(ids.contains("zip"))
    }

    @Test func test_supportsQuality_isTrueOnlyForFormatsTheImageConverterAppliesItTo() {
        let ids = FileFormat.known.filter(\.supportsQuality).map(\.id)
        #expect(Set(ids) == ["jpeg", "heic"])
    }
}
