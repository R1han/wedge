import Foundation
import ImageIO
import UniformTypeIdentifiers
import Testing
@testable import WedgeCore

private actor PeakRecorder {
    private var current = 0
    private(set) var peak = 0
    private(set) var started = 0
    func enter() { current += 1; started += 1; peak = max(peak, current) }
    func leave() { current -= 1 }
}

private struct SlowStub: Converter {
    let id = "stub.slow"
    let from: FileFormat
    let to: FileFormat
    let recorder: PeakRecorder
    let delay: Duration

    func supports(from: FileFormat, to: FileFormat) -> Bool { from == self.from && to == self.to }

    func convert(_ request: ConversionRequest, progress: @Sendable (Double) -> Void) async throws -> ConversionResult {
        await recorder.enter()
        do { try await Task.sleep(for: delay) } catch { await recorder.leave(); throw error }
        await recorder.leave()
        progress(1.0)
        return ConversionResult(outputs: [], bytesWritten: 0)
    }
}

struct ConversionServiceTests {
    private let png = FileFormat.format(forExtension: "png")!
    private let jpeg = FileFormat.format(forExtension: "jpg")!
    private let gif = FileFormat.format(forExtension: "gif")!

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("wedge-svc-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makePNG(in dir: URL, name: String = "src.png") throws -> URL {
        let ctx = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        let url = dir.appendingPathComponent(name)
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
        #expect(CGImageDestinationFinalize(dest))
        return url
    }

    private func touch(_ dir: URL, _ name: String) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try Data([0]).write(to: url)
        return url
    }

    @Test func convertMissingInputThrows() async throws {
        let service = ConversionService(registry: Wedge.defaultRegistry())
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("nope-\(UUID().uuidString).png")
        await #expect(throws: WedgeError.inputNotFound(missing)) {
            _ = try await service.convert(ConversionRequest(input: missing, target: jpeg))
        }
    }

    @Test func convertUnsupportedPairThrows() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = try makePNG(in: dir)
        let service = ConversionService(registry: ConverterRegistry())
        await #expect(throws: WedgeError.unsupportedConversion(from: "png", to: "jpeg")) {
            _ = try await service.convert(ConversionRequest(input: input, target: jpeg))
        }
    }

    @Test func convertPngToJpegSucceeds() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = try makePNG(in: dir)
        let service = ConversionService(registry: Wedge.defaultRegistry())
        let result = try await service.convert(ConversionRequest(input: input, target: jpeg))
        #expect(result.outputs.count == 1)
        #expect(FileManager.default.fileExists(atPath: result.outputs[0].path))
        #expect(result.outputs[0].pathExtension == "jpg")
    }

    @Test func defaultRegistryExposesArchiveExtraction() {
        let registry = Wedge.defaultRegistry()
        let zip = FileFormat.format(forExtension: "zip")!
        let dir = ArchiveConverter.directoryFormat
        #expect(registry.converter(from: zip, to: dir) != nil)
        #expect(registry.pairs().contains { $0.from == zip && $0.to == dir })
    }

    @Test func batchRespectsMaxConcurrent() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let recorder = PeakRecorder()
        let registry = ConverterRegistry()
        registry.register(SlowStub(from: png, to: jpeg, recorder: recorder, delay: .milliseconds(40)))
        let requests = try (0..<12).map { ConversionRequest(input: try touch(dir, "f\($0).png"), target: jpeg) }
        let results = await ConversionService(registry: registry).convertBatch(requests, maxConcurrent: 3)
        #expect(results.count == 12)
        #expect(results.allSatisfy { if case .success = $0 { true } else { false } })
        let peak = await recorder.peak
        #expect(peak <= 3)
        #expect(peak >= 2)
    }

    @Test func batchCancellationMarksPendingCancelled() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let recorder = PeakRecorder()
        let registry = ConverterRegistry()
        registry.register(SlowStub(from: png, to: jpeg, recorder: recorder, delay: .milliseconds(100)))
        let requests = try (0..<20).map { ConversionRequest(input: try touch(dir, "f\($0).png"), target: jpeg) }
        let service = ConversionService(registry: registry)
        let task = Task { await service.convertBatch(requests, maxConcurrent: 1) }
        try await Task.sleep(for: .milliseconds(150))
        task.cancel()
        let results = await task.value
        #expect(results.count == 20)
        let cancelled = results.filter {
            if case .failure(let e) = $0, (e as? WedgeError) == .cancelled { true } else { false }
        }.count
        let succeeded = results.filter { if case .success = $0 { true } else { false } }.count
        #expect(cancelled >= 1)
        #expect(succeeded < 20)
        #expect(await recorder.started < 20)
    }
}
