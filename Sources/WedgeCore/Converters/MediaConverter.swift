import Foundation

/// Audio/video conversion backed by the `ffmpeg` command-line tool. Offline.
public struct MediaConverter: Converter {
    public let id = "media.ffmpeg"

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

    private static let audioFormats: Set<String> = ["mp3", "m4a", "wav", "flac", "aac"]
    private static let videoFormats: Set<String> = ["mp4", "mov", "mkv", "webm"]

    /// Input extension -> ffmpeg demuxer. Forcing it stops a crafted file being probed as a
    /// reference-following demuxer (concat, hls, ...) that could read arbitrary local paths.
    private static let inputDemuxers: [String: String] = [
        "mp4": "mov,mp4,m4a,3gp,3g2,mj2", "m4v": "mov,mp4,m4a,3gp,3g2,mj2",
        "mov": "mov,mp4,m4a,3gp,3g2,mj2", "m4a": "mov,mp4,m4a,3gp,3g2,mj2",
        "mkv": "matroska,webm", "webm": "matroska,webm",
        "mp3": "mp3", "wav": "wav", "flac": "flac", "aac": "aac",
    ]

    /// Generous: long recordings can take a while to transcode.
    private static let timeout: Duration = .seconds(3600)

    public func supports(from: FileFormat, to: FileFormat) -> Bool {
        guard from.id != to.id else { return false }
        if Self.audioFormats.contains(from.id) { return Self.audioFormats.contains(to.id) }
        if Self.videoFormats.contains(from.id) {
            return Self.videoFormats.contains(to.id) || Self.audioFormats.contains(to.id)
        }
        return false
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
              Self.audioFormats.contains(source.id) || Self.videoFormats.contains(source.id)
        else {
            throw WedgeError.invalidInput("Unsupported media type: \(request.input.lastPathComponent)")
        }
        guard supports(from: source, to: request.target) else {
            throw WedgeError.unsupportedConversion(from: source.id, to: request.target.id)
        }
        guard let ffmpeg = locator("ffmpeg") else {
            throw WedgeError.toolNotInstalled(tool: "ffmpeg", installHint: "brew install ffmpeg")
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

        // ffmpeg picks the container from the extension, so the temp file keeps the target extension.
        let tmp = directory.appendingPathComponent(".wedge-\(UUID().uuidString).\(request.target.id)")
        defer { try? fm.removeItem(at: tmp) }

        // `-y` only ever overwrites the temp file; the destination is placed non-destructively below.
        // `-protocol_whitelist file` blocks network and other protocol fetches; the forced input
        // demuxer (when known) blocks probing the input as a reference-following format.
        var args = ["-nostdin", "-y", "-protocol_whitelist", "file"]
        if let demuxer = Self.inputDemuxers[request.input.pathExtension.lowercased()] {
            args += ["-f", demuxer]
        }
        args += ["-i", request.input.path, tmp.path]
        let output = try await runner.run(ffmpeg, args, timeout: Self.timeout)
        progress(0.8)
        guard output.code == 0 else {
            let text = String(decoding: output.stderr, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let tail = text.split(separator: "\n").suffix(5).joined(separator: "\n")
            throw WedgeError.toolFailed(
                tool: "ffmpeg", code: output.code, message: tail.isEmpty ? "ffmpeg failed" : tail)
        }
        guard fm.fileExists(atPath: tmp.path) else {
            throw WedgeError.toolFailed(tool: "ffmpeg", code: 0, message: "ffmpeg produced no output")
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
