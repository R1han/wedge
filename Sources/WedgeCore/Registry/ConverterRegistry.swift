import Foundation

public final class ConverterRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var converters: [Converter] = []

    public init() {}

    public func register(_ converter: Converter) {
        lock.lock()
        defer { lock.unlock() }
        converters.append(converter)
    }

    /// Returns the first registered converter that supports the pair.
    public func converter(from: FileFormat, to: FileFormat) -> Converter? {
        snapshot().first { $0.supports(from: from, to: to) }
    }

    /// Supported (from, to) pairs across registered converters, `FileFormat.known` and the
    /// archive directory pseudo-format (as a target),
    /// deduplicated and sorted by from.id then to.id.
    public func pairs() -> [(from: FileFormat, to: FileFormat)] {
        let current = snapshot()
        var result: [(from: FileFormat, to: FileFormat)] = []
        // Extraction targets the directory pseudo-format, which is not a known file format.
        let targets = FileFormat.known + [ArchiveConverter.directoryFormat]
        for from in FileFormat.known {
            for to in targets where from != to {
                if current.contains(where: { $0.supports(from: from, to: to) }) {
                    result.append((from: from, to: to))
                }
            }
        }
        return result.sorted {
            ($0.from.id, $0.to.id) < ($1.from.id, $1.to.id)
        }
    }

    private func snapshot() -> [Converter] {
        lock.lock()
        defer { lock.unlock() }
        return converters
    }
}
