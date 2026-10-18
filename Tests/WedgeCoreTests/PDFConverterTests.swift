import CoreGraphics
import CoreText
import Foundation
import ImageIO
import PDFKit
import Testing
import UniformTypeIdentifiers
@testable import WedgeCore

struct PDFConverterTests {
    private let pdf = FileFormat.format(forExtension: "pdf")!
    private let png = FileFormat.format(forExtension: "png")!
    private let txt = FileFormat.format(forExtension: "txt")!
    private let converter = PDFConverter()

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PDFConverterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Builds a PDF with one page per string, each drawn as real text.
    private func makePDF(pages: [String], in dir: URL, name: String = "doc.pdf") throws -> URL {
        let url = dir.appendingPathComponent(name)
        var box = CGRect(x: 0, y: 0, width: 300, height: 200)
        let ctx = CGContext(url as CFURL, mediaBox: &box, nil)!
        for text in pages {
            ctx.beginPDFPage(nil)
            let attr = NSAttributedString(string: text, attributes: [
                kCTFontAttributeName as NSAttributedString.Key: CTFontCreateWithName("Helvetica" as CFString, 24, nil),
            ])
            let line = CTLineCreateWithAttributedString(attr)
            ctx.textPosition = CGPoint(x: 20, y: 100)
            CTLineDraw(line, ctx)
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return url
    }

    private func makePNG(in dir: URL) throws -> URL {
        let ctx = CGContext(
            data: nil, width: 64, height: 48, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.9, green: 0.3, blue: 0.2, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 48))
        let url = dir.appendingPathComponent("pic.png")
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
        #expect(CGImageDestinationFinalize(dest))
        return url
    }

    @Test func supportsExpectedPairs() {
        #expect(converter.supports(from: pdf, to: txt))
        #expect(converter.supports(from: pdf, to: png))
        #expect(converter.supports(from: png, to: pdf))
        #expect(!converter.supports(from: txt, to: pdf))
        #expect(!converter.supports(from: png, to: txt))
    }

    @Test func pdfToPngYieldsOneFilePerPage() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = try makePDF(pages: ["Page one", "Page two"], in: dir)
        let result = try await converter.convert(ConversionRequest(input: input, target: png), progress: { _ in })
        #expect(result.outputs.map(\.lastPathComponent) == ["doc-1.png", "doc-2.png"])
        for url in result.outputs {
            let src = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
            let image = try #require(CGImageSourceCreateImageAtIndex(src, 0, nil))
            #expect(image.width >= 600)  // 300pt at 144 dpi
        }
        #expect(result.bytesWritten > 0)
    }

    @Test func pdfToPngDoesNotClobberExistingPages() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = try makePDF(pages: ["A"], in: dir)
        try Data("keep".utf8).write(to: dir.appendingPathComponent("doc-1.png"))
        await #expect(throws: WedgeError.self) {
            _ = try await converter.convert(ConversionRequest(input: input, target: png), progress: { _ in })
        }
        #expect(try Data(contentsOf: dir.appendingPathComponent("doc-1.png")) == Data("keep".utf8))
    }

    @Test func pdfToTxtContainsKnownText() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = try makePDF(pages: ["Hello Wedge", "Second page"], in: dir)
        let result = try await converter.convert(ConversionRequest(input: input, target: txt), progress: { _ in })
        let out = try #require(result.outputs.first)
        #expect(out.pathExtension == "txt")
        let text = try String(contentsOf: out, encoding: .utf8)
        #expect(text.contains("Hello Wedge"))
        #expect(text.contains("Second page"))
    }

    @Test func pngToPdfYieldsOnePagePDF() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = try makePNG(in: dir)
        let result = try await converter.convert(ConversionRequest(input: input, target: pdf), progress: { _ in })
        let out = try #require(result.outputs.first)
        #expect(out.pathExtension == "pdf")
        #expect(PDFDocument(url: out)?.pageCount == 1)
    }

    @Test func missingInputThrowsInputNotFound() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let missing = dir.appendingPathComponent("nope.pdf")
        await #expect(throws: WedgeError.inputNotFound(missing)) {
            _ = try await converter.convert(ConversionRequest(input: missing, target: png), progress: { _ in })
        }
    }

    @Test func nonPDFInputThrowsInvalidInput() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let bad = dir.appendingPathComponent("bad.pdf")
        try Data("not a pdf".utf8).write(to: bad)
        for target in [png, txt] {
            do {
                _ = try await converter.convert(ConversionRequest(input: bad, target: target), progress: { _ in })
                Issue.record("expected invalidInput")
            } catch let error as WedgeError {
                guard case .invalidInput = error else { Issue.record("wrong error \(error)"); continue }
            }
        }
    }

    @Test func zeroPagePDFThrowsInvalidInput() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let empty = dir.appendingPathComponent("empty.pdf")
        let body = "%PDF-1.4\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n2 0 obj<</Type/Pages/Kids[]/Count 0>>endobj\n"
            + "trailer<</Root 1 0 R/Size 3>>\n%%EOF\n"
        try Data(body.utf8).write(to: empty)
        do {
            _ = try await converter.convert(ConversionRequest(input: empty, target: png), progress: { _ in })
            Issue.record("expected invalidInput")
        } catch let error as WedgeError {
            guard case .invalidInput = error else { Issue.record("wrong error \(error)"); return }
        }
    }
}
