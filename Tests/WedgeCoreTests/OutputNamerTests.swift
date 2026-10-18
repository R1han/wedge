import Foundation
import Testing
@testable import WedgeCore

struct OutputNamerTests {
    private let png = FileFormat.format(forExtension: "png")!

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("OutputNamerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func noCollisionUsesBaseName() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = dir.appendingPathComponent("a.jpg")
        let out = OutputNamer().destination(forInput: input, target: png, in: nil, force: false)
        #expect(out.lastPathComponent == "a.png")
        #expect(out.deletingLastPathComponent().standardizedFileURL == dir.standardizedFileURL)
    }

    @Test func collisionAppendsSuffix() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = dir.appendingPathComponent("a.png")
        try Data().write(to: input)
        let first = OutputNamer().destination(forInput: input, target: png, in: nil, force: false)
        #expect(first.lastPathComponent == "a-1.png")
        try Data().write(to: first)
        let second = OutputNamer().destination(forInput: input, target: png, in: nil, force: false)
        #expect(second.lastPathComponent == "a-2.png")
    }

    @Test func forceReturnsBasePathEvenIfExists() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = dir.appendingPathComponent("a.png")
        try Data().write(to: input)
        let out = OutputNamer().destination(forInput: input, target: png, in: nil, force: true)
        #expect(out.lastPathComponent == "a.png")
    }

    @Test func respectsOutputDirectory() throws {
        let dir = try makeTempDir()
        let outDir = try makeTempDir()
        defer {
            try? FileManager.default.removeItem(at: dir)
            try? FileManager.default.removeItem(at: outDir)
        }
        let input = dir.appendingPathComponent("a.jpg")
        let out = OutputNamer().destination(forInput: input, target: png, in: outDir, force: false)
        #expect(out.deletingLastPathComponent().standardizedFileURL == outDir.standardizedFileURL)
        #expect(out.lastPathComponent == "a.png")
    }
}
