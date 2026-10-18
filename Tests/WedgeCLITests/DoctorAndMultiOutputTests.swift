import CoreGraphics
import CoreText
import Foundation
import Testing
@testable import WedgeCLI

@Suite struct DoctorAndMultiOutputTests {
    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("wedge-cli-p2-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makePDF(pages: Int, in dir: URL) -> URL {
        let url = dir.appendingPathComponent("doc.pdf")
        var box = CGRect(x: 0, y: 0, width: 200, height: 100)
        let ctx = CGContext(url as CFURL, mediaBox: &box, nil)!
        for _ in 0..<pages {
            ctx.beginPDFPage(nil)
            ctx.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
            ctx.fill(CGRect(x: 10, y: 10, width: 50, height: 50))
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return url
    }

    @Test func doctorNamesToolsAndExitsZero() async {
        let sink = CLIOutput()
        let code = await WedgeCLI.run(["doctor"], output: sink)
        #expect(code == 0, "stderr: \(sink.stderr)")
        #expect(sink.stdout.contains("pandoc"))
        #expect(sink.stdout.contains("ffmpeg"))
        for line in sink.stdout.split(separator: "\n") {
            #expect(line.contains("found") || line.contains("missing"))
        }
        #expect(sink.stdout.contains("found") || sink.stdout.contains("brew install pandoc"))
    }

    @Test func listIncludesPhase2Pairs() async {
        let sink = CLIOutput()
        let code = await WedgeCLI.run(["list"], output: sink)
        #expect(code == 0)
        #expect(sink.stdout.contains("md -> html"))
        #expect(sink.stdout.contains("pdf -> png"))
    }

    @Test func pdfToPngPrintsEveryOutput() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = makePDF(pages: 2, in: dir)
        let out = dir.appendingPathComponent("out")
        let sink = CLIOutput()
        let code = await WedgeCLI.run(
            ["convert", input.path, "--to", "png", "--out", out.path], output: sink)
        #expect(code == 0, "stderr: \(sink.stderr)")
        let lines = sink.stdout.split(separator: "\n").map(String.init)
        #expect(lines.count == 2)
        for line in lines { #expect(FileManager.default.fileExists(atPath: line)) }
    }
}
