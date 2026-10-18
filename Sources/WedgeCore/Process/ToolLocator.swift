import Foundation

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
