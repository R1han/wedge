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

/// png -> jpeg stub, behaviour chosen by file name prefix:
/// "slow" (also "slowa", "slowb") reports a fixed fraction, then waits until cancelled;
/// "mono" reports 0.8 then 0.3 (a regression), then waits until cancelled;
/// "bad" throws; anything else reports 1 and returns, with no suspension after the report.
private struct GatedConverter: Converter {
    let id = "stub.gated"
    let counter: StartCounter

    func supports(from: FileFormat, to: FileFormat) -> Bool { from.id == "png" && to.id == "jpeg" }

    func convert(_ request: ConversionRequest, progress: @Sendable (Double) -> Void) async throws -> ConversionResult {
        await counter.record()
        let name = request.input.lastPathComponent
        if name.hasPrefix("bad") { throw WedgeError.invalidInput("boom") }
        if name.hasPrefix("mono") {
            progress(0.8)
            progress(0.3)
            try await Task.sleep(for: .seconds(60))
        } else if name.hasPrefix("slow") {
            progress(name.hasPrefix("slowa") ? 0.25 : name.hasPrefix("slowb") ? 0.75 : 0.5)
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
        model.add([try makePNG(in: dir, name: "a.png"), try makePNG(in: dir, name: "b.png")])
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

    @Test func addDedupesPathsThatDifferOnlyBySymlinkPrefix() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let png = try makePNG(in: dir)
        try #require(png.path.hasPrefix("/var/"), "temp dir is expected to live under /var (a symlink to /private/var)")
        let viaPrivate = URL(fileURLWithPath: "/private" + png.path)
        #expect(FileManager.default.fileExists(atPath: viaPrivate.path))
        let model = ConversionModel()
        model.add([png, viaPrivate])
        #expect(model.items.count == 1)
    }

    @Test func targetsAreIntersectionAcrossItems() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let png = try makePNG(in: dir)
        let pdf = dir.appendingPathComponent("doc.pdf")
        try Data([0]).write(to: pdf)
        let model = ConversionModel()
        model.add([png])
        let pngTargets = model.targets
        #expect(pngTargets.contains(jpeg))
        model.clear()
        model.add([pdf])
        let pdfTargets = model.targets
        model.add([png])
        #expect(model.targets == pngTargets.filter(pdfTargets.contains))
        #expect(model.targets.count < pngTargets.count)
    }

    @Test func targetsAreEmptyForNoItems() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let png = try makePNG(in: dir)
        let model = ConversionModel()
        #expect(model.targets.isEmpty)
        model.add([png])
        #expect(!model.targets.isEmpty)
        model.clear()
        #expect(model.targets.isEmpty)
    }

    @Test func convertDrivesItemsToDoneWithRealOutput() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let png = try makePNG(in: dir)
        let model = ConversionModel()
        model.add([png])
        await model.convert(to: jpeg, options: ConversionOptions())
        #expect(!model.isConverting)
        guard case .done(let outputs, let target) = model.items[0].state else {
            Issue.record("expected done, got \(model.items[0].state)")
            return
        }
        #expect(target == jpeg)
        #expect(outputs.count == 1)
        #expect(FileManager.default.fileExists(atPath: outputs[0].path))
        #expect(outputs[0].pathExtension == "jpg")
    }

    @Test func convertReportsReadableFailureForMissingInput() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let png = try makePNG(in: dir, name: "gone.png")
        let model = ConversionModel()
        model.add([png])
        try FileManager.default.removeItem(at: png)
        await model.convert(to: jpeg, options: ConversionOptions())
        guard case .failed(let message) = model.items[0].state else {
            Issue.record("expected failed, got \(model.items[0].state)")
            return
        }
        #expect(message.contains("gone.png"))
        #expect(!message.contains("WedgeError"))
    }

    @Test func toolFailureMessageIsFirstLineAndTruncated() {
        let multi = ConversionModel.message(for: WedgeError.toolFailed(tool: "ffmpeg", code: 1, message: "\n\n first line \nsecond line\nthird"))
        #expect(multi == "ffmpeg failed: first line")
        let long = ConversionModel.message(for: WedgeError.toolFailed(tool: "ffmpeg", code: 1, message: String(repeating: "x", count: 500)))
        #expect(long == "ffmpeg failed: " + String(repeating: "x", count: 200) + "\u{2026}")
    }

    @Test func runningStateCarriesProgressFraction() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (model, _) = gatedModel()
        model.add([try makePNG(in: dir, name: "slow.png")])
        let run = Task { await model.convert(to: jpeg, options: ConversionOptions()) }
        let sawProgress = await waitUntil { model.items[0].state == .running(0.5) }
        #expect(sawProgress)
        model.cancel()
        await run.value
    }

    @Test func progressIsRoutedToTheRightItem() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (model, _) = gatedModel()
        model.add([try makePNG(in: dir, name: "slowa.png"), try makePNG(in: dir, name: "slowb.png")])
        let run = Task { await model.convert(to: jpeg, options: ConversionOptions()) }
        let routed = await waitUntil {
            model.items[0].state == .running(0.25) && model.items[1].state == .running(0.75)
        }
        #expect(routed)
        model.cancel()
        await run.value
    }

    @Test func progressNeverMovesBackwards() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (model, _) = gatedModel()
        model.add([try makePNG(in: dir, name: "mono.png")])
        let run = Task { await model.convert(to: jpeg, options: ConversionOptions()) }
        #expect(await waitUntil { model.items[0].state == .running(0.8) })
        try await Task.sleep(for: .milliseconds(100))
        #expect(model.items[0].state == .running(0.8))
        model.cancel()
        await run.value
    }

    @Test func fastItemIsDoneWhileSlowItemIsStillRunning() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (model, _) = gatedModel()
        model.add([try makePNG(in: dir, name: "fast.png"), try makePNG(in: dir, name: "slow.png")])
        let run = Task { await model.convert(to: jpeg, options: ConversionOptions()) }
        let seen = await waitUntil {
            if case .done = model.items[0].state { model.items[1].state == .running(0.5) } else { false }
        }
        #expect(seen)
        #expect(model.isConverting)
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

    @Test func cancelMarksUnfinishedItemsCancelledAndKeepsFinishedOnes() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (model, _) = gatedModel()
        model.add([try makePNG(in: dir, name: "fast.png"), try makePNG(in: dir, name: "slow.png")])
        let run = Task { await model.convert(to: jpeg, options: ConversionOptions()) }
        let ready = await waitUntil {
            if case .done = model.items[0].state { model.items[1].state == .running(0.5) } else { false }
        }
        #expect(ready)
        model.cancel()
        await run.value
        #expect(!model.isConverting)
        guard case .done = model.items[0].state else {
            Issue.record("finished item should stay done")
            return
        }
        #expect(model.items[1].state == .cancelled)
    }

    @Test func onlyUnfinishedItemsAreConverted() async throws {
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

    @Test func doneItemIsReconvertedWhenTheTargetDiffers() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let tiff = FileFormat.format(forExtension: "tiff")!
        let model = ConversionModel()
        model.add([try makePNG(in: dir)])
        await model.convert(to: jpeg, options: ConversionOptions())
        await model.convert(to: tiff, options: ConversionOptions())
        guard case .done(let outputs, let target) = model.items[0].state else {
            Issue.record("expected done, got \(model.items[0].state)")
            return
        }
        #expect(target == tiff)
        #expect(outputs[0].pathExtension == "tif")
    }

    @Test func failedItemCanBeRetried() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let model = ConversionModel()
        let png = try makePNG(in: dir, name: "later.png")
        model.add([png])
        try FileManager.default.removeItem(at: png)
        await model.convert(to: jpeg, options: ConversionOptions())
        guard case .failed = model.items[0].state else {
            Issue.record("expected failed, got \(model.items[0].state)")
            return
        }
        _ = try makePNG(in: dir, name: "later.png")
        await model.convert(to: jpeg, options: ConversionOptions())
        guard case .done = model.items[0].state else {
            Issue.record("expected done after retry, got \(model.items[0].state)")
            return
        }
    }

    @Test func addDuringRunLeavesNewItemPendingAndOutOfTheBatch() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (model, counter) = gatedModel()
        model.add([try makePNG(in: dir, name: "slow.png")])
        let run = Task { await model.convert(to: jpeg, options: ConversionOptions()) }
        #expect(await waitUntil { model.isConverting })
        model.add([try makePNG(in: dir, name: "late.png")])
        #expect(model.items.count == 2)
        #expect(model.items[1].state == .pending)
        model.cancel()
        await run.value
        #expect(model.items[1].state == .pending)
        #expect(await counter.started == 1)
    }

    @Test func redroppingAFinishedFileResetsItToPending() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let png = try makePNG(in: dir)
        let model = ConversionModel()
        model.add([png])
        await model.convert(to: jpeg, options: ConversionOptions())
        model.add([png])
        #expect(model.items.count == 1)
        #expect(model.items[0].state == .pending)
    }

    @Test func redroppingAFailedOrCancelledFileResetsItToPending() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (model, _) = gatedModel()
        let bad = try makePNG(in: dir, name: "bad.png")
        let slow = try makePNG(in: dir, name: "slow.png")
        model.add([bad, slow])
        let run = Task { await model.convert(to: jpeg, options: ConversionOptions()) }
        #expect(await waitUntil {
            if case .failed = model.items[0].state { model.items[1].state == .running(0.5) } else { false }
        })
        model.cancel()
        await run.value
        #expect(model.items[0].state == .failed("Invalid input: boom"))
        #expect(model.items[1].state == .cancelled)
        model.add([bad, slow])
        #expect(model.items.map(\.state) == [.pending, .pending])
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
        guard case .done(let second, _) = model.items[0].state else {
            Issue.record("expected done")
            return
        }
        let jpgs = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".jpg") }
        #expect(jpgs.count == 2)
        #expect(second[0].lastPathComponent == "src-1.jpg")
    }

    @Test func missingFileIsUnsupportedWithReason() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let model = ConversionModel()
        model.add([dir.appendingPathComponent("missing.png")])
        #expect(model.items[0].state == .unsupported("File not found"))
        #expect(!model.items[0].isConvertible)
        #expect(model.targets.isEmpty)
    }

    @Test func unknownFileTypeIsUnsupportedWithReason() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let odd = dir.appendingPathComponent("doc.pdf")
        try Data([0]).write(to: odd)
        let (model, _) = gatedModel()
        model.add([odd])
        #expect(model.items[0].state == .unsupported("Unsupported file type"))
    }

    @Test func targetsIgnoreUnsupportedItems() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let png = try makePNG(in: dir)
        let model = ConversionModel()
        model.add([png])
        let pngTargets = model.targets
        model.add([dir.appendingPathComponent("missing.png")])
        #expect(model.items.count == 2)
        #expect(model.targets == pngTargets)
        #expect(model.items[0].isConvertible)
        #expect(!model.items[1].isConvertible)
    }

    @Test func unsupportedItemIsSkippedByConvertAndKeepsItsState() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let png = try makePNG(in: dir)
        let model = ConversionModel()
        model.add([png, dir.appendingPathComponent("missing.png")])
        await model.convert(to: jpeg, options: ConversionOptions())
        guard case .done = model.items[0].state else {
            Issue.record("expected done, got \(model.items[0].state)")
            return
        }
        #expect(model.items[1].state == .unsupported("File not found"))
    }

    @Test func redroppingAnUnsupportedFileReevaluatesIt() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let model = ConversionModel()
        let later = dir.appendingPathComponent("later.png")
        model.add([later])
        #expect(model.items[0].state == .unsupported("File not found"))
        _ = try makePNG(in: dir, name: "later.png")
        model.add([later])
        #expect(model.items.count == 1)
        #expect(model.items[0].state == .pending)
        #expect(!model.targets.isEmpty)
    }

    @Test func hasWorkReflectsConvertibleItemsAndTarget() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let model = ConversionModel()
        #expect(!model.hasWork(for: jpeg))
        model.add([dir.appendingPathComponent("missing.png")])
        #expect(!model.hasWork(for: jpeg))
        model.add([try makePNG(in: dir)])
        #expect(model.hasWork(for: jpeg))
    }

    @Test func removeDropsItemAndRecomputesTargets() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let png = try makePNG(in: dir)
        let pdf = dir.appendingPathComponent("doc.pdf")
        try Data([0]).write(to: pdf)
        let model = ConversionModel()
        model.add([png, pdf])
        let narrowed = model.targets
        model.remove(model.items[1].id)
        #expect(model.items.count == 1)
        #expect(model.targets.count > narrowed.count)
        #expect(model.targets.contains(jpeg))
        model.remove(UUID())
        #expect(model.items.count == 1)
    }

    @Test func addingAFolderIsConvertibleToAnArchive() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let folder = dir.appendingPathComponent("stuff")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data([1]).write(to: folder.appendingPathComponent("a.txt"))
        let model = ConversionModel()
        model.add([folder])
        #expect(model.items[0].isConvertible)
        #expect(model.items[0].state == .pending)
        #expect(model.targets.contains { $0.id == "zip" })
    }

    @Test func dropWithNoFileURLsSetsNoticeUntilNextSuccessfulAdd() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let model = ConversionModel()
        #expect(model.notice == nil)
        model.addDropped([])
        #expect(model.notice == "Only files and folders can be added")
        #expect(model.items.isEmpty)
        model.addDropped([try makePNG(in: dir)])
        #expect(model.notice == nil)
        #expect(model.items.count == 1)
    }

    @Test func removeIsRefusedWhileConverting() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (model, _) = gatedModel()
        model.add([try makePNG(in: dir, name: "slow.png")])
        let run = Task { await model.convert(to: jpeg, options: ConversionOptions()) }
        #expect(await waitUntil { model.isConverting })
        model.remove(model.items[0].id)
        #expect(model.items.count == 1)
        model.cancel()
        await run.value
    }
}
