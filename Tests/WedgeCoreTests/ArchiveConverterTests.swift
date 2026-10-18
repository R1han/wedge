import Foundation
import Testing
@testable import WedgeCore

struct ArchiveConverterTests {
    private let zip = FileFormat.format(forExtension: "zip")!
    private let tar = FileFormat.format(forExtension: "tar")!

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ArchiveConverterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Creates `<root>/src/{a.txt,b.txt}` and returns the `src` directory.
    private func makeFixture(in root: URL) throws -> URL {
        let src = root.appendingPathComponent("src", isDirectory: true)
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        try "alpha".write(to: src.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "beta beta".write(to: src.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
        return src
    }

    private func roundTrip(_ format: FileFormat) async throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let src = try makeFixture(in: root)
        let archiveDir = root.appendingPathComponent("archives", isDirectory: true)
        try FileManager.default.createDirectory(at: archiveDir, withIntermediateDirectories: true)
        let converter = ArchiveConverter()

        let created = try await converter.convert(
            ConversionRequest(input: src, target: format, outputDirectory: archiveDir), progress: { _ in })
        let archive = try #require(created.outputs.first)
        #expect(archive.pathExtension == format.extensions[0])
        #expect(created.bytesWritten > 0)

        let outDir = root.appendingPathComponent("out", isDirectory: true)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let extracted = try await converter.convert(
            ConversionRequest(input: archive, target: ArchiveConverter.directoryFormat, outputDirectory: outDir),
            progress: { _ in })
        let dir = try #require(extracted.outputs.first)
        // `--keepParent` / tar -C parent keeps the top-level folder name.
        let inner = dir.appendingPathComponent("src", isDirectory: true)
        #expect(try String(contentsOf: inner.appendingPathComponent("a.txt"), encoding: .utf8) == "alpha")
        #expect(try String(contentsOf: inner.appendingPathComponent("b.txt"), encoding: .utf8) == "beta beta")
    }

    @Test func zipRoundTrip() async throws { try await roundTrip(zip) }
    @Test func tarRoundTrip() async throws { try await roundTrip(tar) }

    @Test(arguments: ["zip", "tar"])
    func extractExceedsEntryGuardThrows(ext: String) async throws {
        let format = FileFormat.format(forExtension: ext)!
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let src = try makeFixture(in: root)
        let created = try await ArchiveConverter().convert(
            ConversionRequest(input: src, target: format, outputDirectory: root), progress: { _ in })
        let archive = try #require(created.outputs.first)
        let outDir = root.appendingPathComponent("out", isDirectory: true)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        let guarded = ArchiveConverter(maxEntries: 1)
        await #expect {
            try await guarded.convert(
                ConversionRequest(input: archive, target: ArchiveConverter.directoryFormat, outputDirectory: outDir),
                progress: { _ in })
        } throws: { error in
            if case .resourceLimitExceeded = error as? WedgeError { return true }
            return false
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: outDir.path).isEmpty)
    }

    @Test(arguments: ["zip", "tar"])
    func extractExceedsByteGuardThrows(ext: String) async throws {
        let format = FileFormat.format(forExtension: ext)!
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let src = try makeFixture(in: root)
        let created = try await ArchiveConverter().convert(
            ConversionRequest(input: src, target: format, outputDirectory: root), progress: { _ in })
        let archive = try #require(created.outputs.first)

        let guarded = ArchiveConverter(maxBytes: 5)
        await #expect {
            try await guarded.convert(
                ConversionRequest(input: archive, target: ArchiveConverter.directoryFormat, outputDirectory: root),
                progress: { _ in })
        } throws: { error in
            if case .resourceLimitExceeded = error as? WedgeError { return true }
            return false
        }
    }

    @Test func missingInputThrowsInputNotFound() async throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let missing = root.appendingPathComponent("nope")
        await #expect(throws: WedgeError.inputNotFound(missing)) {
            try await ArchiveConverter().convert(
                ConversionRequest(input: missing, target: zip), progress: { _ in })
        }
    }

    @Test func createDoesNotClobberExistingOutput() async throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let src = try makeFixture(in: root)
        let existing = root.appendingPathComponent("src.zip")
        try "keep".write(to: existing, atomically: true, encoding: .utf8)
        let result = try await ArchiveConverter().convert(
            ConversionRequest(input: src, target: zip, outputDirectory: root), progress: { _ in })
        #expect(result.outputs.first?.lastPathComponent == "src-1.zip")
        #expect(try String(contentsOf: existing, encoding: .utf8) == "keep")
    }

    @Test func supportsMatrix() {
        let c = ArchiveConverter()
        let png = FileFormat.format(forExtension: "png")!
        #expect(c.supports(from: png, to: zip))
        #expect(c.supports(from: zip, to: ArchiveConverter.directoryFormat))
        #expect(c.supports(from: tar, to: ArchiveConverter.directoryFormat))
        #expect(!c.supports(from: png, to: png))
        #expect(!c.supports(from: zip, to: tar))
    }
}
