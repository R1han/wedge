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

    private func makeNoisyPNG(in dir: URL) throws -> URL {
        let w = 128, h = 128
        var px = [UInt8](repeating: 255, count: w * h * 4)
        var seed: UInt32 = 12345
        for i in 0..<(w * h) {
            for c in 0..<3 {
                seed = seed &* 1664525 &+ 1013904223
                px[i * 4 + c] = UInt8(truncatingIfNeeded: seed >> 24)
            }
        }
        let ctx = px.withUnsafeMutableBytes {
            CGContext(data: $0.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        }
        let image = ctx.makeImage()!
        let url = dir.appendingPathComponent("noise.png")
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, nil)
        #expect(CGImageDestinationFinalize(dest))
        return url
    }

    private func makeGIF(in dir: URL, frames: Int) throws -> URL {
        let url = dir.appendingPathComponent("anim.gif")
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frames, nil)!
        for f in 0..<frames {
            let ctx = CGContext(data: nil, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.setFillColor(CGColor(red: CGFloat(f) / CGFloat(frames), green: 0.5, blue: 0.5, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
            CGImageDestinationAddImage(dest, ctx.makeImage()!, [
                kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.1]] as CFDictionary)
        }
        #expect(CGImageDestinationFinalize(dest))
        return url
    }

    private func frameCount(_ url: URL) throws -> Int {
        CGImageSourceGetCount(try #require(CGImageSourceCreateWithURL(url as CFURL, nil)))
    }

    @Test func lowerQualityProducesSmallerJpeg() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = try makeNoisyPNG(in: dir)
        let high = try await ImageConverter().convert(
            ConversionRequest(input: input, target: jpeg, options: ConversionOptions(quality: 0.95)), progress: { _ in })
        let low = try await ImageConverter().convert(
            ConversionRequest(input: input, target: jpeg, options: ConversionOptions(quality: 0.1)), progress: { _ in })
        #expect(low.bytesWritten < high.bytesWritten)
    }

    @Test func invalidOptionsAreRejected() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = try makePNG(in: dir)
        await #expect(throws: WedgeError.self) {
            _ = try await ImageConverter().convert(
                ConversionRequest(input: input, target: jpeg, options: ConversionOptions(quality: 2)), progress: { _ in })
        }
        await #expect(throws: WedgeError.self) {
            _ = try await ImageConverter().convert(
                ConversionRequest(input: input, target: jpeg, options: ConversionOptions(maxDimension: 0)), progress: { _ in })
        }
    }

    @Test func writeRefusesToClobberWithoutForce() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let target = dir.appendingPathComponent("out.jpg")
        try Data("old".utf8).write(to: target)
        #expect(throws: WedgeError.outputExists(target)) {
            try ImageConverter.write(Data("new".utf8), to: target, force: false)
        }
        #expect(try Data(contentsOf: target) == Data("old".utf8))
        try ImageConverter.write(Data("new".utf8), to: target, force: true)
        #expect(try Data(contentsOf: target) == Data("new".utf8))
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasPrefix(".wedge-") }
        #expect(leftovers.isEmpty)
    }

    @Test func forceOverwriteOfInputReplacesItSafely() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = try makePNG(in: dir)
        let result = try await ImageConverter().convert(
            ConversionRequest(input: input, target: png, options: ConversionOptions(maxDimension: 32, force: true)),
            progress: { _ in })
        let out = try #require(result.outputs.first)
        #expect(out.standardizedFileURL == input.standardizedFileURL)
        let info = try properties(of: out)
        #expect(info.type == "public.png")
        #expect(info.width == 32 && info.height == 24)
    }

    @Test func sameFormatWithoutTransformCopiesVerbatim() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = try makePNG(in: dir, withExif: true)
        let out = dir.appendingPathComponent("copies", isDirectory: true)
        let result = try await ImageConverter().convert(
            ConversionRequest(input: input, target: png, outputDirectory: out), progress: { _ in })
        #expect(try Data(contentsOf: try #require(result.outputs.first)) == Data(contentsOf: input))
    }

    @Test func gifFramesSurviveSameFormatConversion() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = try makeGIF(in: dir, frames: 3)
        let gif = FileFormat.format(forExtension: "gif")!
        #expect(try frameCount(input) == 3)
        let copied = try await ImageConverter().convert(
            ConversionRequest(input: input, target: gif), progress: { _ in })
        #expect(try frameCount(try #require(copied.outputs.first)) == 3)
        let strip = try await ImageConverter().convert(
            ConversionRequest(input: input, target: gif, options: ConversionOptions(stripMetadata: true)),
            progress: { _ in })
        #expect(try frameCount(try #require(strip.outputs.first)) == 3)
    }

    @Test func heicEncodesWhenEncoderAvailable() async throws {
        let available = (CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []).contains(UTType.heic.identifier)
        guard available else { return }
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = try makePNG(in: dir)
        let heic = FileFormat.format(forExtension: "heic")!
        do {
            let result = try await ImageConverter().convert(
                ConversionRequest(input: input, target: heic, options: ConversionOptions(quality: 0.5)),
                progress: { _ in })
            #expect(try properties(of: try #require(result.outputs.first)).width == 64)
        } catch WedgeError.toolFailed {
            return // encoder listed but unusable on this host
        }
    }

    @Test func undecodableInputThrowsInvalidInput() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let bad = dir.appendingPathComponent("bad.png")
        try Data("not an image".utf8).write(to: bad)
        await #expect(throws: WedgeError.invalidInput("Cannot decode image: bad.png")) {
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
