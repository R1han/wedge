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

    public static let known: [FileFormat] = [
        FileFormat(id: "png", extensions: ["png"], category: .image),
        FileFormat(id: "jpeg", extensions: ["jpg", "jpeg"], category: .image),
        FileFormat(id: "heic", extensions: ["heic", "heif"], category: .image),
        FileFormat(id: "tiff", extensions: ["tif", "tiff"], category: .image),
        FileFormat(id: "gif", extensions: ["gif"], category: .image),
        FileFormat(id: "bmp", extensions: ["bmp"], category: .image),
        FileFormat(id: "webp", extensions: ["webp"], category: .image),
        FileFormat(id: "pdf", extensions: ["pdf"], category: .document),
        FileFormat(id: "zip", extensions: ["zip"], category: .archive),
        FileFormat(id: "tar", extensions: ["tar"], category: .archive),
    ]

    /// Case-insensitive lookup by file extension (without the leading dot).
    public static func format(forExtension ext: String) -> FileFormat? {
        let needle = ext.lowercased()
        return known.first { $0.extensions.contains(needle) }
    }
}
