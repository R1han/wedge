import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import WedgeCore

struct ImageConverterTests {
    private let jpeg = FileFormat.format(forExtension: "jpg")!
    private let png = FileFormat.format(forExtension: "png")!

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImageConverterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Generates a 64x48 PNG with CoreGraphics, optionally with an injected EXIF dictionary.
    private func makePNG(in dir: URL, withExif: Bool = false) throws -> URL {
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil, width: 64, height: 48, bitsPerComponent: 8, bytesPerRow: 0,
            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.9, green: 0.3, blue: 0.2, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 48))
        ctx.setFillColor(CGColor(red: 0.1, green: 0.4, blue: 0.8, alpha: 1))
        ctx.fill(CGRect(x: 16, y: 12, width: 32, height: 24))
        let image = ctx.makeImage()!
        let url = dir.appendingPathComponent("src.png")
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        var props: [CFString: Any] = [:]
        if withExif {
            props[kCGImagePropertyExifDictionary] = [kCGImagePropertyExifUserComment: "secret-comment"]
        }
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        #expect(CGImageDestinationFinalize(dest))
        return url
    }

    private func properties(of url: URL) throws -> (type: String, width: Int, height: Int, props: [CFString: Any]) {
        let src = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let props = try #require(CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any])
        return (
            CGImageSourceGetType(src) as String? ?? "",
            props[kCGImagePropertyPixelWidth] as? Int ?? 0,
            props[kCGImagePropertyPixelHeight] as? Int ?? 0,
            props)
    }

    @Test func pngToJpegProducesReadableJpeg() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = try makePNG(in: dir)
        let result = try await ImageConverter().convert(
            ConversionRequest(input: input, target: jpeg), progress: { _ in })
        let out = try #require(result.outputs.first)
        #expect(FileManager.default.fileExists(atPath: out.path))
        #expect(result.bytesWritten > 0)
        let info = try properties(of: out)
        #expect(info.type == "public.jpeg")
        #expect(info.width == 64 && info.height == 48)
    }

    @Test func maxDimensionResizesProportionally() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = try makePNG(in: dir)
        let result = try await ImageConverter().convert(
            ConversionRequest(input: input, target: jpeg, options: ConversionOptions(maxDimension: 32)),
            progress: { _ in })
        let info = try properties(of: try #require(result.outputs.first))
        #expect(info.width == 32 && info.height == 24)
    }

    @Test func stripMetadataRemovesExif() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = try makePNG(in: dir, withExif: true)
        #expect(try properties(of: input).props[kCGImagePropertyExifDictionary] != nil)

        let kept = try await ImageConverter().convert(
            ConversionRequest(input: input, target: jpeg), progress: { _ in })
        #expect(try properties(of: try #require(kept.outputs.first)).props[kCGImagePropertyExifDictionary] != nil)

        let stripped = try await ImageConverter().convert(
            ConversionRequest(input: input, target: jpeg, options: ConversionOptions(stripMetadata: true, force: true)),
            progress: { _ in })
        let info = try properties(of: try #require(stripped.outputs.first))
        let exif = info.props[kCGImagePropertyExifDictionary] as? [CFString: Any]
        #expect(exif?[kCGImagePropertyExifUserComment] == nil)
    }

    @Test func missingInputThrowsInputNotFound() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let missing = dir.appendingPathComponent("nope.png")
        await #expect(throws: WedgeError.inputNotFound(missing)) {
            _ = try await ImageConverter().convert(
                ConversionRequest(input: missing, target: jpeg), progress: { _ in })
        }
    }

    @Test func undecodableInputThrowsInvalidInput() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let bad = dir.appendingPathComponent("bad.png")
        try Data("not an image".utf8).write(to: bad)
        await #expect(throws: WedgeError.self) {
            _ = try await ImageConverter().convert(
                ConversionRequest(input: bad, target: jpeg), progress: { _ in })
        }
    }

    @Test func existingOutputIsNotClobberedWithoutForce() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = try makePNG(in: dir)
        let first = try await ImageConverter().convert(
            ConversionRequest(input: input, target: jpeg), progress: { _ in })
        let second = try await ImageConverter().convert(
            ConversionRequest(input: input, target: jpeg), progress: { _ in })
        #expect(first.outputs != second.outputs)
    }

    @Test func supportsMatrix() {
        let c = ImageConverter()
        #expect(c.id == "image.imageio")
        #expect(c.supports(from: png, to: jpeg))
        #expect(c.supports(from: jpeg, to: png))
        let pdf = FileFormat.format(forExtension: "pdf")!
        #expect(!c.supports(from: png, to: pdf))
    }
}
