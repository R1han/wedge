import Foundation
import Testing
@testable import WedgeCore

struct PandocConverterTests {
    private static let pandocInstalled = ToolLocator.shared.path(for: "pandoc") != nil

    private let md = FileFormat.format(forExtension: "md")!
    private let html = FileFormat.format(forExtension: "html")!
    private let docx = FileFormat.format(forExtension: "docx")!

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PandocConverterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeMarkdown(in dir: URL) throws -> URL {
        let url = dir.appendingPathComponent("note.md")
        try "# Quarterly Heading\n\nSome *emphasised* text.\n".write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @Test func supportsDocumentPairsOnly() {
        let c = PandocConverter()
        #expect(c.supports(from: md, to: html))
        #expect(c.supports(from: docx, to: md))
        #expect(!c.supports(from: md, to: md))
        #expect(!c.supports(from: md, to: FileFormat.format(forExtension: "png")!))
    }

    @Test(.enabled(if: PandocConverterTests.pandocInstalled))
    func markdownToHTMLContainsConvertedHeading() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = try makeMarkdown(in: dir)
        let result = try await PandocConverter().convert(
            ConversionRequest(input: input, target: html, outputDirectory: nil, options: .init()),
            progress: { _ in })
        let out = try #require(result.outputs.first)
        #expect(out.pathExtension == "html")
        let text = try String(contentsOf: out, encoding: .utf8)
        #expect(text.contains("<html"))
        #expect(text.contains("<h1"))
        #expect(text.contains("Quarterly Heading"))
        #expect(result.bytesWritten > 0)
    }

    @Test(.enabled(if: PandocConverterTests.pandocInstalled))
    func markdownToDocxIsNonEmpty() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = try makeMarkdown(in: dir)
        let result = try await PandocConverter().convert(
            ConversionRequest(input: input, target: docx, outputDirectory: nil, options: .init()),
            progress: { _ in })
        let out = try #require(result.outputs.first)
        #expect(out.pathExtension == "docx")
        let size = try FileManager.default.attributesOfItem(atPath: out.path)[.size] as? Int ?? 0
        #expect(size > 0)
        #expect(result.bytesWritten == size)
    }

    @Test(.enabled(if: PandocConverterTests.pandocInstalled))
    func plainTextToHTMLAndMarkdownSucceed() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = dir.appendingPathComponent("plain.txt")
        try "Hello plain world\n".write(to: input, atomically: true, encoding: .utf8)
        for target in [html, md] {
            let result = try await PandocConverter().convert(
                ConversionRequest(input: input, target: target, outputDirectory: nil, options: .init()),
                progress: { _ in })
            let text = try String(contentsOf: try #require(result.outputs.first), encoding: .utf8)
            #expect(text.contains("Hello plain world"))
        }
    }

    @Test(.enabled(if: PandocConverterTests.pandocInstalled))
    func markdownToRTFIsWrapped() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = try makeMarkdown(in: dir)
        let result = try await PandocConverter().convert(
            ConversionRequest(input: input, target: FileFormat.format(forExtension: "rtf")!,
                              outputDirectory: nil, options: .init()),
            progress: { _ in })
        let text = try String(contentsOf: try #require(result.outputs.first), encoding: .utf8)
        #expect(text.hasPrefix("{\\rtf"))
    }

    @Test func inputPathFollowsDoubleDashSeparator() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = try makeMarkdown(in: dir)
        let recorder = RecordingRunner()
        let converter = PandocConverter(locator: { _ in URL(fileURLWithPath: "/usr/bin/true") }, runner: recorder)
        _ = try? await converter.convert(
            ConversionRequest(input: input, target: html, outputDirectory: nil, options: .init()),
            progress: { _ in })
        let args = try #require(recorder.lastArgs)
        #expect(Array(args.suffix(2)) == ["--", input.path])
        #expect(args.contains("-s"))
    }

    @Test func missingInputThrowsInputNotFound() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let missing = dir.appendingPathComponent("nope.md")
        await #expect(throws: WedgeError.inputNotFound(missing)) {
            _ = try await PandocConverter().convert(
                ConversionRequest(input: missing, target: html, outputDirectory: nil, options: .init()),
                progress: { _ in })
        }
    }

    @Test func absentPandocThrowsToolNotInstalled() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = try makeMarkdown(in: dir)
        let converter = PandocConverter(locator: { _ in nil }, runner: FailingRunner())
        await #expect(throws: WedgeError.toolNotInstalled(tool: "pandoc", installHint: "brew install pandoc")) {
            _ = try await converter.convert(
                ConversionRequest(input: input, target: html, outputDirectory: nil, options: .init()),
                progress: { _ in })
        }
    }

    @Test func nonzeroExitMapsToToolFailedAndLeavesNoOutput() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = try makeMarkdown(in: dir)
        let converter = PandocConverter(
            locator: { _ in URL(fileURLWithPath: "/usr/bin/true") }, runner: StubRunner(code: 3, stderr: "boom"))
        do {
            _ = try await converter.convert(
                ConversionRequest(input: input, target: html, outputDirectory: nil, options: .init()),
                progress: { _ in })
            Issue.record("expected toolFailed")
        } catch WedgeError.toolFailed(_, let code, let message) {
            #expect(code == 3)
            #expect(message.contains("boom"))
        }
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(files == ["note.md"])
    }
}

private struct FailingRunner: ProcessRunning {
    func run(_ executable: URL, _ args: [String], timeout: Duration) async throws -> ProcessRunner.Output {
        Issue.record("runner must not be called")
        throw WedgeError.cancelled
    }
}

private struct StubRunner: ProcessRunning {
    let code: Int32
    let stderr: String
    func run(_ executable: URL, _ args: [String], timeout: Duration) async throws -> ProcessRunner.Output {
        ProcessRunner.Output(stdout: Data(), stderr: Data(stderr.utf8), code: code)
    }
}

private final class RecordingRunner: ProcessRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var args: [String]?
    var lastArgs: [String]? { lock.withLock { args } }
    func run(_ executable: URL, _ args: [String], timeout: Duration) async throws -> ProcessRunner.Output {
        lock.withLock { self.args = args }
        return ProcessRunner.Output(stdout: Data(), stderr: Data(), code: 1)
    }
}
