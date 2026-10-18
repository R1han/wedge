import Foundation

/// Chooses the destination path for a conversion. Never overwrites an existing
/// file unless `force` is set.
public struct OutputNamer: Sendable {
    public init() {}

    public func destination(forInput input: URL, target: FileFormat, in directory: URL?, force: Bool) -> URL {
        let dir = directory ?? input.deletingLastPathComponent()
        let stem = input.deletingPathExtension().lastPathComponent
        let ext = target.extensions.first ?? target.id
        let base = dir.appendingPathComponent("\(stem).\(ext)")
        if force { return base }

        let fm = FileManager.default
        var candidate = base
        var n = 1
        while fm.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent("\(stem)-\(n).\(ext)")
            n += 1
        }
        return candidate
    }
}
