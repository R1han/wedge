import Testing
@testable import WedgeCore

@Suite struct FileFormatCatalogTests {
    @Test(arguments: [
        ("md", FormatCategory.document), ("markdown", .document), ("docx", .document),
        ("html", .document), ("epub", .document), ("txt", .document), ("rtf", .document),
        ("mp4", .video), ("mov", .video), ("mkv", .video), ("webm", .video),
        ("mp3", .audio), ("m4a", .audio), ("wav", .audio), ("flac", .audio), ("aac", .audio),
    ])
    func test_formatForExtension_resolvesCategory(ext: String, category: FormatCategory) {
        #expect(FileFormat.format(forExtension: ext)?.category == category)
    }
}
