import Foundation

/// Document-to-document conversion backed by the `pandoc` command-line tool. Offline.
public struct PandocConverter: Converter {
    public let id = "doc.pandoc"

    public typealias Locator = @Sendable (String) -> URL?

    private let locator: Locator
    private let runner: any ProcessRunning

    public init(
        locator: @escaping Locator = { ToolLocator.shared.path(for: $0) },
        runner: any ProcessRunning = ProcessRunner()
    ) {
        self.locator = locator
        self.runner = runner
    }

    /// FileFormat id -> pandoc format name.
    private static let pandocNames: [String: String] = [
        "md": "markdown", "html": "html", "docx": "docx", "epub": "epub", "txt": "plain", "rtf": "rtf",
    ]

    /// Generous: large documents with embedded media can take a while.
    private static let timeout: Duration = .seconds(600)

    public func supports(from: FileFormat, to: FileFormat) -> Bool {
        from.id != to.id && Self.pandocNames[from.id] != nil && Self.pandocNames[to.id] != nil
    }

    public func convert(
        _ request: ConversionRequest,
        progress: @Sendable (Double) -> Void
    ) async throws -> ConversionResult {
        let fm = FileManager.default
        guard fm.fileExists(atPath: request.input.path) else {
            throw WedgeError.inputNotFound(request.input)
        }
        guard let source = FileFormat.format(forExtension: request.input.pathExtension),
              let fromName = Self.pandocNames[source.id]
        else {
            throw WedgeError.invalidInput("Unsupported document type: \(request.input.lastPathComponent)")
        }
        guard let toName = Self.pandocNames[request.target.id], source.id != request.target.id else {
            throw WedgeError.unsupportedConversion(from: source.id, to: request.target.id)
        }
        guard let pandoc = locator("pandoc") else {
            throw WedgeError.toolNotInstalled(tool: "pandoc", installHint: "brew install pandoc")
        }
        progress(0.0)

        let options = request.options
        let destination = OutputNamer().destination(
            forInput: request.input, target: request.target,
            in: request.outputDirectory, force: options.force)
        if !options.force && fm.fileExists(atPath: destination.path) {
            throw WedgeError.outputExists(destination)
        }
        let directory = destination.deletingLastPathComponent()
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)

        let tmp = directory.appendingPathComponent(".wedge-\(UUID().uuidString).tmp")
        defer { try? fm.removeItem(at: tmp) }

        let output = try await runner.run(
            pandoc,
            [request.input.path, "-f", fromName, "-t", toName, "-o", tmp.path],
            timeout: Self.timeout)
        progress(0.8)
        guard output.code == 0 else {
            let message = String(decoding: output.stderr, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw WedgeError.toolFailed(
                tool: "pandoc", code: output.code, message: message.isEmpty ? "pandoc failed" : message)
        }
        guard fm.fileExists(atPath: tmp.path) else {
            throw WedgeError.toolFailed(tool: "pandoc", code: 0, message: "pandoc produced no output")
        }

        let size = (try? fm.attributesOfItem(atPath: tmp.path)[.size] as? Int) ?? 0
        if options.force, fm.fileExists(atPath: destination.path) {
            _ = try fm.replaceItemAt(destination, withItemAt: tmp)
        } else {
            do {
                try fm.moveItem(at: tmp, to: destination)
            } catch let error as CocoaError where error.code == .fileWriteFileExists {
                throw WedgeError.outputExists(destination)
            }
        }
        progress(1.0)
        return ConversionResult(outputs: [destination], bytesWritten: size)
    }
}
