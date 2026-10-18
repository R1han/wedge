import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import WedgeCLI

@Suite struct CLIIntegrationTests {
    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("wedge-cli-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makePNG(in dir: URL) throws -> URL {
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = try #require(CGContext(
            data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        let image = try #require(ctx.makeImage())
        let url = dir.appendingPathComponent("src.png")
        let dest = try #require(CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, nil)
        #expect(CGImageDestinationFinalize(dest))
        return url
    }

    @Test func convertPngToJpegCreatesOutput() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = try makePNG(in: dir)
        let out = dir.appendingPathComponent("out")
        let sink = CLIOutput()
        let code = await WedgeCLI.run(
            ["convert", input.path, "--to", "jpeg", "--out", out.path, "--quality", "0.8"], output: sink)
        #expect(code == 0, "stderr: \(sink.stderr)")
        let files = try FileManager.default.contentsOfDirectory(atPath: out.path)
        #expect(files.count == 1)
        #expect(files.first?.hasSuffix(".jpg") == true || files.first?.hasSuffix(".jpeg") == true)
    }

    @Test func convertMissingInputFailsWithMessage() async throws {
        let sink = CLIOutput()
        let code = await WedgeCLI.run(["convert", "/nonexistent/nope.png", "--to", "jpeg"], output: sink)
        #expect(code == 66)
        #expect(sink.stderr.contains("nope.png"))
        #expect(sink.stderr.lowercased().contains("not found"))
    }

    @Test func convertUnknownTargetFails() async throws {
        let sink = CLIOutput()
        let code = await WedgeCLI.run(["convert", "x.png", "--to", "bogus"], output: sink)
        #expect(code == 64)
        #expect(sink.stderr.contains("bogus"))
    }

    @Test func convertExistingOutputIsNotClobberedUnlessForced() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = try makePNG(in: dir)
        func count() throws -> Int { try FileManager.default.contentsOfDirectory(atPath: dir.path).count }
        #expect(await WedgeCLI.run(["convert", input.path, "--to", "jpeg"], output: CLIOutput()) == 0)
        #expect(try count() == 2)
        #expect(await WedgeCLI.run(["convert", input.path, "--to", "jpeg"], output: CLIOutput()) == 0)
        #expect(try count() == 3)  // second run got a new name
        #expect(await WedgeCLI.run(["convert", input.path, "--to", "jpeg", "--force"], output: CLIOutput()) == 0)
        #expect(try count() == 3)  // forced run overwrote the base name
    }

    @Test func invalidQualityIsRejected() async throws {
        let sink = CLIOutput()
        let code = await WedgeCLI.run(["convert", "x.png", "--to", "jpeg", "--quality", "2"], output: sink)
        #expect(code == 64)
        #expect(sink.stderr.contains("quality"))
    }

    @Test func listIncludesPngToJpeg() async throws {
        let sink = CLIOutput()
        let code = await WedgeCLI.run(["list"], output: sink)
        #expect(code == 0)
        #expect(sink.stdout.contains("png -> jpeg"))
        #expect(sink.stdout.contains("-> dir"))
    }

    @Test func unknownCommandFails() async throws {
        let sink = CLIOutput()
        let code = await WedgeCLI.run(["frobnicate"], output: sink)
        #expect(code == 64)
        #expect(!sink.stderr.isEmpty)
    }

    @Test func convertToDirExtractsZip() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let src = dir.appendingPathComponent("src")
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        try "hello".write(to: src.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let zip = dir.appendingPathComponent("bundle.zip")
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-c", "-k", "--sequesterRsrc", src.path, zip.path]
        try ditto.run()
        ditto.waitUntilExit()
        #expect(ditto.terminationStatus == 0)

        let out = dir.appendingPathComponent("out")
        let sink = CLIOutput()
        let code = await WedgeCLI.run(["convert", zip.path, "--to", "dir", "--out", out.path], output: sink)
        #expect(code == 0, "stderr: \(sink.stderr)")
        let reported = sink.stdout.split(separator: "\n").map { URL(fileURLWithPath: String($0)) }
        let destination = try #require(reported.first)
        #expect(destination.path.hasPrefix(out.path))
        let found = FileManager.default.enumerator(atPath: destination.path)?
            .compactMap { $0 as? String }.filter { $0.hasSuffix("a.txt") } ?? []
        #expect(found.count == 1)
        let text = try String(contentsOf: destination.appendingPathComponent(try #require(found.first)), encoding: .utf8)
        #expect(text == "hello")
    }

    @Test func convertFolderToZipCreatesArchive() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let folder = dir.appendingPathComponent("docs")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "x".write(to: folder.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let out = dir.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let sink = CLIOutput()
        let code = await WedgeCLI.run(["convert", folder.path, "--to", "zip", "--out", out.path], output: sink)
        #expect(code == 0, "stderr: \(sink.stderr)")
        #expect(FileManager.default.fileExists(atPath: out.appendingPathComponent("docs.zip").path))
    }

    @Test func convertPlainFileToTarCreatesArchive() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("notes.txt")
        try "x".write(to: file, atomically: true, encoding: .utf8)
        let out = dir.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let sink = CLIOutput()
        let code = await WedgeCLI.run(["convert", file.path, "--to", "tar", "--out", out.path], output: sink)
        #expect(code == 0, "stderr: \(sink.stderr)")
        #expect(FileManager.default.fileExists(atPath: out.appendingPathComponent("notes.tar").path))
    }

    @Test func convertMaxDimDownscales() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = try makePNG(in: dir)  // 8x8
        let out = dir.appendingPathComponent("out")
        let code = await WedgeCLI.run(
            ["convert", input.path, "--to", "jpeg", "--out", out.path, "--max-dim", "4"], output: CLIOutput())
        #expect(code == 0)
        let file = try #require(try FileManager.default.contentsOfDirectory(atPath: out.path).first)
        let source = try #require(CGImageSourceCreateWithURL(out.appendingPathComponent(file) as CFURL, nil))
        let props = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect((props[kCGImagePropertyPixelWidth] as? Int ?? 99) <= 4)
        #expect((props[kCGImagePropertyPixelHeight] as? Int ?? 99) <= 4)
    }

    @Test func convertUnsupportedConversionFails() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = try makePNG(in: dir)
        let sink = CLIOutput()
        let code = await WedgeCLI.run(["convert", input.path, "--to", "mp3"], output: sink)
        #expect(code == 65)
        #expect(sink.stderr.contains("unsupported conversion"))
        #expect(sink.stderr.contains("png"))
    }
}
