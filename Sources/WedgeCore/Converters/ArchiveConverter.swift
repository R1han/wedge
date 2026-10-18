import Foundation

/// Creates and extracts zip/tar archives with the system tools (`ditto`, `tar`),
/// refusing to extract archives that exceed entry-count or size limits.
public struct ArchiveConverter: Converter {
    public static let defaultMaxEntries = 100_000
    public static let defaultMaxBytes: Int64 = 2 * 1024 * 1024 * 1024

    /// Pseudo-format used as the `target` of an extraction (the result is a directory).
    public static let directoryFormat = FileFormat(id: "dir", extensions: [], category: .other)

    public let id = "archive.systool"
    public let maxEntries: Int
    public let maxBytes: Int64

    private let runner = ProcessRunner()
    private let ditto = URL(fileURLWithPath: "/usr/bin/ditto")
    private let tarTool = URL(fileURLWithPath: "/usr/bin/tar")
    private let unzip = URL(fileURLWithPath: "/usr/bin/unzip")

    public init(maxEntries: Int = ArchiveConverter.defaultMaxEntries,
                maxBytes: Int64 = ArchiveConverter.defaultMaxBytes) {
        self.maxEntries = maxEntries
        self.maxBytes = maxBytes
    }

    public func supports(from: FileFormat, to: FileFormat) -> Bool {
        if from.category == .archive { return to.id == Self.directoryFormat.id }
        return to.id == "zip" || to.id == "tar"
    }

    public func convert(
        _ request: ConversionRequest,
        progress: @Sendable (Double) -> Void
    ) async throws -> ConversionResult {
        let fm = FileManager.default
        guard fm.fileExists(atPath: request.input.path) else {
            throw WedgeError.inputNotFound(request.input)
        }
        let from = FileFormat.format(forExtension: request.input.pathExtension)
            ?? FileFormat(id: "unknown", extensions: [], category: .other)
        guard supports(from: from, to: request.target) else {
            throw WedgeError.unsupportedConversion(from: from.id, to: request.target.id)
        }
        progress(0)
        let result = from.category == .archive
            ? try await extract(request, archiveFormat: from)
            : try await create(request)
        progress(1)
        return result
    }

    // MARK: - Create

    private func create(_ request: ConversionRequest) async throws -> ConversionResult {
        let dest = OutputNamer().destination(
            forInput: request.input, target: request.target,
            in: request.outputDirectory, force: request.options.force)
        let input = request.input
        let output: ProcessRunner.Output
        if request.target.id == "zip" {
            output = try await runner.run(
                ditto, ["-c", "-k", "--sequesterRsrc", "--keepParent", input.path, dest.path])
        } else {
            output = try await runner.run(
                tarTool, ["-cf", dest.path, "-C", input.deletingLastPathComponent().path, input.lastPathComponent])
        }
        guard output.code == 0 else {
            try? FileManager.default.removeItem(at: dest)
            throw toolFailure(request.target.id == "zip" ? "ditto" : "tar", output)
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: dest.path)[.size] as? Int) ?? 0
        return ConversionResult(outputs: [dest], bytesWritten: size)
    }

    // MARK: - Extract

    private func extract(_ request: ConversionRequest, archiveFormat: FileFormat) async throws -> ConversionResult {
        let isZip = archiveFormat.id == "zip"
        try await enforceLimits(archive: request.input, isZip: isZip)

        let fm = FileManager.default
        let parent = request.outputDirectory ?? request.input.deletingLastPathComponent()
        let stem = request.input.deletingPathExtension().lastPathComponent
        var dest = parent.appendingPathComponent(stem, isDirectory: true)
        if !request.options.force {
            var n = 1
            while fm.fileExists(atPath: dest.path) {
                dest = parent.appendingPathComponent("\(stem)-\(n)", isDirectory: true)
                n += 1
            }
        }
        let existedBefore = fm.fileExists(atPath: dest.path)
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)

        let output = isZip
            ? try await runner.run(ditto, ["-x", "-k", request.input.path, dest.path])
            : try await runner.run(tarTool, ["-xf", request.input.path, "-C", dest.path])
        guard output.code == 0 else {
            if !existedBefore { try? fm.removeItem(at: dest) }
            throw toolFailure(isZip ? "ditto" : "tar", output)
        }
        return ConversionResult(outputs: [dest], bytesWritten: Int(directorySize(dest)))
    }

    /// Lists the archive and throws `resourceLimitExceeded` before anything is extracted.
    private func enforceLimits(archive: URL, isZip: Bool) async throws {
        let listing = isZip
            ? try await runner.run(unzip, ["-l", archive.path])
            : try await runner.run(tarTool, ["-tvf", archive.path])
        guard listing.code == 0 else { throw toolFailure(isZip ? "unzip" : "tar", listing) }
        let text = String(decoding: listing.stdout, as: UTF8.self)
        let (count, bytes) = isZip ? Self.parseZipListing(text) : Self.parseTarListing(text)
        if count > maxEntries {
            throw WedgeError.resourceLimitExceeded("archive has \(count) entries (limit \(maxEntries))")
        }
        if bytes > maxBytes {
            throw WedgeError.resourceLimitExceeded("archive expands to \(bytes) bytes (limit \(maxBytes))")
        }
    }

    /// `unzip -l`: rows sit between two dashed separator lines; the first column is the length.
    static func parseZipListing(_ text: String) -> (count: Int, bytes: Int64) {
        var count = 0
        var bytes: Int64 = 0
        var separators = 0
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("---------") {
                separators += 1
                continue
            }
            guard separators == 1 else { continue }
            guard let first = trimmed.split(separator: " ").first, let size = Int64(first) else { continue }
            count += 1
            bytes += size
        }
        return (count, bytes)
    }

    /// `tar -tvf` (bsdtar): `perms links owner group size date... name`; size is the fifth field.
    static func parseTarListing(_ text: String) -> (count: Int, bytes: Int64) {
        var count = 0
        var bytes: Int64 = 0
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            count += 1
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            if fields.count > 4, let size = Int64(fields[4]) { bytes += size }
        }
        return (count, bytes)
    }

    // MARK: - Helpers

    private func toolFailure(_ tool: String, _ output: ProcessRunner.Output) -> WedgeError {
        .toolFailed(
            tool: tool, code: output.code,
            message: String(decoding: output.stderr, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func directorySize(_ dir: URL) -> Int64 {
        guard let walker = FileManager.default.enumerator(
            at: dir, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in walker {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            if values?.isRegularFile == true { total += Int64(values?.fileSize ?? 0) }
        }
        return total
    }
}
