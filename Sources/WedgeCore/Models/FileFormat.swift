import Foundation

public enum FormatCategory: String, Sendable {
    case image, archive, document, audio, video, data, other
}

public struct FileFormat: Hashable, Sendable {
    public let id: String
    public let extensions: [String]
    public let category: FormatCategory

    public init(id: String, extensions: [String], category: FormatCategory) {
        self.id = id
        self.extensions = extensions
        self.category = category
    }

    /// Whether `ConversionOptions.quality` changes the encoded output for this target.
    public var supportsQuality: Bool { category == .image && (id == "jpeg" || id == "heic") }

    public static let known: [FileFormat] = [
        FileFormat(id: "png", extensions: ["png"], category: .image),
        FileFormat(id: "jpeg", extensions: ["jpg", "jpeg"], category: .image),
        FileFormat(id: "heic", extensions: ["heic", "heif"], category: .image),
        FileFormat(id: "tiff", extensions: ["tif", "tiff"], category: .image),
        FileFormat(id: "gif", extensions: ["gif"], category: .image),
        FileFormat(id: "bmp", extensions: ["bmp"], category: .image),
        FileFormat(id: "webp", extensions: ["webp"], category: .image),
        FileFormat(id: "pdf", extensions: ["pdf"], category: .document),
        FileFormat(id: "md", extensions: ["md", "markdown"], category: .document),
        FileFormat(id: "html", extensions: ["html", "htm"], category: .document),
        FileFormat(id: "docx", extensions: ["docx"], category: .document),
        FileFormat(id: "epub", extensions: ["epub"], category: .document),
        FileFormat(id: "txt", extensions: ["txt"], category: .document),
        FileFormat(id: "rtf", extensions: ["rtf"], category: .document),
        FileFormat(id: "mp3", extensions: ["mp3"], category: .audio),
        FileFormat(id: "m4a", extensions: ["m4a"], category: .audio),
        FileFormat(id: "wav", extensions: ["wav"], category: .audio),
        FileFormat(id: "flac", extensions: ["flac"], category: .audio),
        FileFormat(id: "aac", extensions: ["aac"], category: .audio),
        FileFormat(id: "mp4", extensions: ["mp4", "m4v"], category: .video),
        FileFormat(id: "mov", extensions: ["mov"], category: .video),
        FileFormat(id: "mkv", extensions: ["mkv"], category: .video),
        FileFormat(id: "webm", extensions: ["webm"], category: .video),
        FileFormat(id: "zip", extensions: ["zip"], category: .archive),
        FileFormat(id: "tar", extensions: ["tar"], category: .archive),
    ]

    /// Case-insensitive lookup by file extension (without the leading dot).
    public static func format(forExtension ext: String) -> FileFormat? {
        let needle = ext.lowercased()
        return known.first { $0.extensions.contains(needle) }
    }
}
