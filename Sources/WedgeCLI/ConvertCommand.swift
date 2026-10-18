import ArgumentParser
import Foundation
import WedgeCore

struct ConvertCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "convert", abstract: "Convert a file to another format.")

    @Argument(help: "Input file.") var input: String
    @Option(name: .long, help: "Target format id (see `wedge list`), or `dir` to extract an archive.")
    var to: String
    @Option(name: .long, help: "Output directory (default: next to the input).") var out: String?
    @Option(name: .long, help: "Quality from 0 to 1.") var quality: Double?
    @Option(name: .customLong("max-dim"), help: "Maximum width/height in pixels.") var maxDim: Int?
    @Flag(name: .customLong("strip-metadata"), help: "Remove metadata from the output.") var stripMetadata = false
    @Flag(name: .long, help: "Overwrite an existing output.") var force = false

    func validate() throws {
        if let quality, !(0...1).contains(quality) {
            throw ValidationError("--quality must be between 0 and 1")
        }
        if let maxDim, maxDim <= 0 {
            throw ValidationError("--max-dim must be a positive integer")
        }
    }

    static func resolveTarget(_ id: String) -> FileFormat? {
        let needle = id.lowercased()
        if needle == ArchiveConverter.directoryFormat.id { return ArchiveConverter.directoryFormat }
        return FileFormat.known.first { $0.id == needle }
    }

    func execute(output: CLIOutput) async -> Int32 {
        guard let target = Self.resolveTarget(to) else {
            let ids = (FileFormat.known.map(\.id) + [ArchiveConverter.directoryFormat.id]).joined(separator: ", ")
            output.writeErr("error: unknown target format '\(to)' (known: \(ids))")
            return 64
        }
        let request = ConversionRequest(
            input: URL(fileURLWithPath: input),
            target: target,
            outputDirectory: out.map { URL(fileURLWithPath: $0, isDirectory: true) },
            options: ConversionOptions(
                quality: quality, maxDimension: maxDim, stripMetadata: stripMetadata, force: force))
        do {
            let result = try await ConversionService(registry: Wedge.defaultRegistry()).convert(request)
            for url in result.outputs { output.writeOut(url.path) }
            return 0
        } catch {
            output.writeErr(WedgeCLI.describe(error))
            return WedgeCLI.exitCode(for: error)
        }
    }
}
