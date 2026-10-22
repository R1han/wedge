import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
import WedgeCore
@testable import WedgeApp

private actor StartCounter {
    private(set) var started = 0
    func record() { started += 1 }
}

/// png -> jpeg stub: names starting with "slow" report 0.5 then wait until cancelled,
/// anything else reports 1 and returns without suspending again, so cancellation cannot reach it.
private struct GatedConverter: Converter {
    let id = "stub.gated"
    let counter: StartCounter

    func supports(from: FileFormat, to: FileFormat) -> Bool { from.id == "png" && to.id == "jpeg" }

    func convert(_ request: ConversionRequest, progress: @Sendable (Double) -> Void) async throws -> ConversionResult {
        await counter.record()
        if request.input.lastPathComponent.hasPrefix("slow") {
            progress(0.5)
            try await Task.sleep(for: .seconds(60))
        } else {
            progress(1)
        }
        return ConversionResult(outputs: [request.input.deletingPathExtension().appendingPathExtension("jpg")], bytesWritten: 1)
    }
}

@MainActor
@Suite struct ConversionModelTests {
    private let jpeg = FileFormat.format(forExtension: "jpg")!

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("wedge-model-\(UUID().uuidString)")
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

    private func gatedModel() -> (ConversionModel, StartCounter) {
        let counter = StartCounter()
        let registry = ConverterRegistry()
        registry.register(GatedConverter(counter: counter))
        return (ConversionModel(service: ConversionService(registry: registry)), counter)
    }

    private func waitUntil(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<1000 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    @Test func addAppendsPendingItems() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let model = ConversionModel()
        model.add([dir.appendingPathComponent("a.png"), dir.appendingPathComponent("b.png")])
        #expect(model.items.count == 2)
        #expect(model.items.allSatisfy { $0.state == .pending })
    }

    @Test func addIgnoresDuplicatesIncludingUnstandardizedPaths() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = dir.appendingPathComponent("a.png")
        let sneaky = dir.appendingPathComponent("sub/../a.png")
        let model = ConversionModel()
        model.add([a, a, sneaky])
        model.add([a])
        #expect(model.items.count == 1)
    }

    @Test func availableTargetsIsIntersectionAcrossInputs() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let png = try makePNG(in: dir)
        let pdf = dir.appendingPathComponent("doc.pdf")
        try Data([0]).write(to: pdf)
        let model = ConversionModel()
        let pngTargets = model.availableTargets(for: [png])
        let pdfTargets = model.availableTargets(for: [pdf])
        #expect(pngTargets.contains(jpeg))
        let both = model.availableTargets(for: [png, pdf])
        #expect(both == pngTargets.filter(pdfTargets.contains))
        #expect(both.count < pngTargets.count)
    }

    @Test func availableTargetsIsEmptyForNoInputsOrAnyMissingInput() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let png = try makePNG(in: dir)
        let model = ConversionModel()
        #expect(model.availableTargets(for: []).isEmpty)
        #expect(model.availableTargets(for: [png, dir.appendingPathComponent("missing.png")]).isEmpty)
    }

    @Test func convertDrivesItemsToDoneWithRealOutput() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let png = try makePNG(in: dir)
        let model = ConversionModel()
        model.add([png])
        await model.convert(to: jpeg, options: ConversionOptions())
        #expect(!model.isConverting)
        guard case .done(let outputs) = model.items[0].state else {
            Issue.record("expected done, got \(model.items[0].state)")
            return
        }
        #expect(outputs.count == 1)
        #expect(FileManager.default.fileExists(atPath: outputs[0].path))
        #expect(outputs[0].pathExtension == "jpg")
    }

    @Test func convertReportsReadableFailureForMissingInput() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let missing = dir.appendingPathComponent("gone.png")
        let model = ConversionModel()
        model.add([missing])
        await model.convert(to: jpeg, options: ConversionOptions())
        guard case .failed(let message) = model.items[0].state else {
            Issue.record("expected failed, got \(model.items[0].state)")
            return
        }
        #expect(message.contains("gone.png"))
        #expect(!message.contains("WedgeError"))
    }

    @Test func runningStateCarriesProgressFraction() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (model, _) = gatedModel()
        model.add([try makePNG(in: dir, name: "slow.png")])
        let run = Task { await model.convert(to: jpeg, options: ConversionOptions()) }
        let sawProgress = await waitUntil {
            if case .running(let f) = model.items[0].state { f == 0.5 } else { false }
        }
        #expect(sawProgress)
        model.cancel()
        await run.value
    }

    @Test func secondConvertWhileRunningIsNoOp() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (model, counter) = gatedModel()
        model.add([try makePNG(in: dir, name: "slow.png")])
        let run = Task { await model.convert(to: jpeg, options: ConversionOptions()) }
        #expect(await waitUntil { model.isConverting })
        await model.convert(to: jpeg, options: ConversionOptions())
        #expect(model.isConverting)
        model.cancel()
        await run.value
        #expect(await counter.started == 1)
    }

    @Test func cancelFailsUnfinishedItemsAndKeepsFinishedOnes() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (model, _) = gatedModel()
        model.add([try makePNG(in: dir, name: "fast.png"), try makePNG(in: dir, name: "slow.png")])
        let run = Task { await model.convert(to: jpeg, options: ConversionOptions()) }
        let ready = await waitUntil {
            model.items[0].state == .running(1) && model.items[1].state == .running(0.5)
        }
        #expect(ready)
        model.cancel()
        await run.value
        #expect(!model.isConverting)
        guard case .done = model.items[0].state else {
            Issue.record("finished item should stay done")
            return
        }
        #expect(model.items[1].state == .failed("Cancelled"))
    }

    @Test func onlyPendingAndFailedItemsAreConverted() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (model, counter) = gatedModel()
        model.add([try makePNG(in: dir, name: "fast.png")])
        await model.convert(to: jpeg, options: ConversionOptions())
        #expect(await counter.started == 1)
        model.add([try makePNG(in: dir, name: "other.png")])
        await model.convert(to: jpeg, options: ConversionOptions())
        #expect(await counter.started == 2)
        await model.convert(to: jpeg, options: ConversionOptions())
        #expect(await counter.started == 2)
    }

    @Test func clearIsRefusedWhileConverting() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (model, _) = gatedModel()
        model.add([try makePNG(in: dir, name: "slow.png")])
        let run = Task { await model.convert(to: jpeg, options: ConversionOptions()) }
        #expect(await waitUntil { model.isConverting })
        model.clear()
        #expect(model.items.count == 1)
        model.cancel()
        await run.value
        model.clear()
        #expect(model.items.isEmpty)
    }

    @Test func convertingSameInputTwiceNeverOverwrites() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let png = try makePNG(in: dir)
        let model = ConversionModel()
        model.add([png])
        await model.convert(to: jpeg, options: ConversionOptions())
        model.clear()
        model.add([png])
        await model.convert(to: jpeg, options: ConversionOptions())
        guard case .done(let second) = model.items[0].state else {
            Issue.record("expected done")
            return
        }
        let jpgs = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".jpg") }
        #expect(jpgs.count == 2)
        #expect(second[0].lastPathComponent == "src-1.jpg")
    }
}
