import Foundation

/// An external command-line tool the converters depend on, with the hint shown when it is missing.
public struct ExternalTool: Sendable, Equatable {
    public let name: String
    public let installHint: String

    public init(name: String, installHint: String) {
        self.name = name
        self.installHint = installHint
    }

    public static let pandoc = ExternalTool(name: "pandoc", installHint: "brew install pandoc")
    public static let ffmpeg = ExternalTool(name: "ffmpeg", installHint: "brew install ffmpeg")
    public static let all: [ExternalTool] = [.pandoc, .ffmpeg]
}

/// Locates external command-line tools. GUI apps inherit a minimal `PATH`, so the
/// common Homebrew prefixes are searched in addition to `$PATH`.
public struct ToolLocator: Sendable {
    public static let shared = ToolLocator()

    private static let fallbackDirectories = ["/opt/homebrew/bin", "/usr/local/bin"]

    public init() {}

    /// The executable URL for `tool`, or nil when it is not installed.
    public func path(for tool: String) -> URL? {
        guard !tool.isEmpty, !tool.contains("/") else { return nil }
        let envPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let directories = envPath.split(separator: ":").map(String.init) + Self.fallbackDirectories
        for directory in directories {
            let candidate = URL(fileURLWithPath: directory, isDirectory: true).appendingPathComponent(tool)
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
               !isDirectory.boolValue,
               FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }
}
