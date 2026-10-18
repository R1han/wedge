import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

/// PDF text extraction, page rasterisation and image-to-PDF, backed by PDFKit. Offline, no external tools.
public struct PDFConverter: Converter {
    public let id = "pdf.pdfkit"

    public init() {}

    private static let imageInputs: Set<String> = ["png", "jpeg", "tiff", "heic"]
    /// Page rendering resolution; PDF user space is 72 points per inch.
    private static let renderScale: CGFloat = 2.0

    public func supports(from: FileFormat, to: FileFormat) -> Bool {
        switch (from.id, to.id) {
        case ("pdf", "txt"), ("pdf", "png"): return true
        case (let f, "pdf"): return Self.imageInputs.contains(f)
        default: return false
        }
    }

    public func convert(
        _ request: ConversionRequest,
        progress: @Sendable (Double) -> Void
    ) async throws -> ConversionResult {
        let fm = FileManager.default
        guard fm.fileExists(atPath: request.input.path) else {
            throw WedgeError.inputNotFound(request.input)
        }
        let from = FileFormat.format(forExtension: request.input.pathExtension)?.id
        let to = request.target.id
        progress(0.0)
        if let dir = request.outputDirectory {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let result: ConversionResult
        switch (from, to) {
        case ("pdf", "txt"): result = try toText(request)
        case ("pdf", "png"): result = try toPNGs(request, progress: progress)
        case (let f?, "pdf") where Self.imageInputs.contains(f): result = try imageToPDF(request)
        default:
            throw WedgeError.unsupportedConversion(from: from ?? request.input.pathExtension, to: to)
        }
        progress(1.0)
        return result
    }

    private func openDocument(_ url: URL) throws -> PDFDocument {
        guard let doc = PDFDocument(url: url), doc.pageCount > 0 else {
            throw WedgeError.invalidInput("Cannot read PDF or it has no pages: \(url.lastPathComponent)")
        }
        return doc
    }

    private func toText(_ request: ConversionRequest) throws -> ConversionResult {
        let doc = try openDocument(request.input)
        let text = (0..<doc.pageCount)
            .map { doc.page(at: $0)?.string ?? "" }
            .joined(separator: "\n\n")
        let destination = OutputNamer().destination(
            forInput: request.input, target: request.target,
            in: request.outputDirectory, force: request.options.force)
        let data = Data(text.utf8)
        try ImageConverter.write(data, to: destination, force: request.options.force)
        return ConversionResult(outputs: [destination], bytesWritten: data.count)
    }

    private func toPNGs(
        _ request: ConversionRequest,
        progress: @Sendable (Double) -> Void
    ) throws -> ConversionResult {
        let doc = try openDocument(request.input)
        let force = request.options.force
        let dir = request.outputDirectory ?? request.input.deletingLastPathComponent()
        let stem = request.input.deletingPathExtension().lastPathComponent
        let count = doc.pageCount
        let fm = FileManager.default
        var outputs: [URL] = []
        var created: [URL] = []
        var total = 0
        do {
            for index in 0..<count {
                guard let page = doc.page(at: index) else {
                    throw WedgeError.invalidInput("Cannot read page \(index + 1)")
                }
                // OutputNamer suffixes on collision (or reuses the name under force), like every other converter.
                let destination = OutputNamer().destination(
                    forInput: dir.appendingPathComponent("\(stem)-\(index + 1).pdf"),
                    target: request.target, in: dir, force: force)
                let existed = fm.fileExists(atPath: destination.path)
                let data = try Self.renderPNG(page)
                try ImageConverter.write(data, to: destination, force: force)
                if !existed { created.append(destination) }
                outputs.append(destination)
                total += data.count
                progress(0.9 * Double(index + 1) / Double(count))
            }
        } catch {
            // All-or-nothing: remove pages this run created. Files replaced under force cannot be restored.
            for url in created { try? fm.removeItem(at: url) }
            throw error
        }
        return ConversionResult(outputs: outputs, bytesWritten: total)
    }

    private static func renderPNG(_ page: PDFPage) throws -> Data {
        let box = page.bounds(for: .mediaBox)
        let width = max(1, Int((box.width * renderScale).rounded()))
        let height = max(1, Int((box.height * renderScale).rounded()))
        guard let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else {
            throw WedgeError.toolFailed(tool: "pdf.pdfkit", code: 1, message: "Cannot allocate drawing context")
        }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.scaleBy(x: renderScale, y: renderScale)
        ctx.translateBy(x: -box.minX, y: -box.minY)
        page.draw(with: .mediaBox, to: ctx)
        guard let image = ctx.makeImage() else {
            throw WedgeError.toolFailed(tool: "pdf.pdfkit", code: 1, message: "Page render failed")
        }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw WedgeError.toolFailed(tool: "pdf.pdfkit", code: 1, message: "No PNG encoder")
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw WedgeError.toolFailed(tool: "pdf.pdfkit", code: 1, message: "PNG encoding failed")
        }
        return data as Data
    }

    private func imageToPDF(_ request: ConversionRequest) throws -> ConversionResult {
        guard let source = CGImageSourceCreateWithURL(request.input as CFURL, nil),
              CGImageSourceGetCount(source) > 0,
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw WedgeError.invalidInput("Cannot decode image: \(request.input.lastPathComponent)")
        }
        // The thumbnailer applies the EXIF/TIFF orientation transform; full-size so nothing is downscaled.
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(cgImage.width, cgImage.height),
        ]
        let oriented = CGImageSourceCreateThumbnailAtIndex(source, 0, opts as CFDictionary) ?? cgImage
        let size = CGSize(width: oriented.width, height: oriented.height)
        guard let page = PDFPage(image: PlatformImage(cgImage: oriented, size: size)) else {
            throw WedgeError.toolFailed(tool: id, code: 1, message: "Cannot create PDF page")
        }
        let doc = PDFDocument()
        doc.insert(page, at: 0)
        guard let data = doc.dataRepresentation() else {
            throw WedgeError.toolFailed(tool: id, code: 1, message: "PDF encoding failed")
        }
        let destination = OutputNamer().destination(
            forInput: request.input, target: request.target,
            in: request.outputDirectory, force: request.options.force)
        try ImageConverter.write(data, to: destination, force: request.options.force)
        return ConversionResult(outputs: [destination], bytesWritten: data.count)
    }
}

#if canImport(AppKit)
import AppKit
private typealias PlatformImage = NSImage
#endif
