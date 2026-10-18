import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Raster image conversion backed by ImageIO and CoreGraphics. Offline, no external tools.
public struct ImageConverter: Converter {
    public let id = "image.imageio"

    public init() {}

    private static let utis: [String: UTType] = [
        "png": .png, "jpeg": .jpeg, "heic": .heic, "tiff": .tiff, "gif": .gif, "bmp": .bmp,
    ]

    /// Formats whose encoder has no alpha channel; transparency is flattened onto white.
    private static let opaqueFormats: Set<String> = ["jpeg", "bmp"]

    private static let multiFrameFormats: Set<String> = ["gif", "tiff"]

    /// Property entries worth carrying across when metadata is kept.
    private static var metadataKeys: [CFString] { [
        kCGImagePropertyExifDictionary, kCGImagePropertyTIFFDictionary, kCGImagePropertyGPSDictionary,
        kCGImagePropertyIPTCDictionary, kCGImagePropertyOrientation,
        kCGImagePropertyDPIWidth, kCGImagePropertyDPIHeight, kCGImagePropertyGIFDictionary,
    ] }

    public func supports(from: FileFormat, to: FileFormat) -> Bool {
        from.category == .image && to.category == .image
            && Self.utis[from.id] != nil && Self.utis[to.id] != nil
    }

    public func convert(
        _ request: ConversionRequest,
        progress: @Sendable (Double) -> Void
    ) async throws -> ConversionResult {
        let fm = FileManager.default
        guard fm.fileExists(atPath: request.input.path) else {
            throw WedgeError.inputNotFound(request.input)
        }
        guard let targetType = Self.utis[request.target.id] else {
            throw WedgeError.unsupportedConversion(from: "image", to: request.target.id)
        }
        let options = request.options
        if let max = options.maxDimension, max <= 0 {
            throw WedgeError.invalidInput("maxDimension must be positive")
        }
        if let q = options.quality, !(0.0...1.0).contains(q) {
            throw WedgeError.invalidInput("quality must be between 0 and 1")
        }
        progress(0.0)

        guard let source = CGImageSourceCreateWithURL(request.input as CFURL, nil),
              CGImageSourceGetCount(source) > 0
        else {
            throw WedgeError.invalidInput("Cannot decode image: \(request.input.lastPathComponent)")
        }
        let sourceType = CGImageSourceGetType(source).flatMap { UTType($0 as String) }
        let sameFormat = sourceType == targetType
        let hasTransform = options.maxDimension != nil || options.quality != nil || options.stripMetadata

        let destination = OutputNamer().destination(
            forInput: request.input, target: request.target,
            in: request.outputDirectory, force: options.force)
        if let dir = request.outputDirectory {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        let bytes: Data
        if sameFormat && !hasTransform {
            // Nothing to change: copy verbatim so every frame, page and tag survives.
            if destination.standardizedFileURL == request.input.standardizedFileURL {
                let size = (try? fm.attributesOfItem(atPath: request.input.path)[.size] as? Int) ?? 0
                progress(1.0)
                return ConversionResult(outputs: [destination], bytesWritten: size)
            }
            bytes = try Data(contentsOf: request.input)
            progress(0.8)
        } else {
            bytes = try encode(source: source, request: request, targetType: targetType,
                               keepAllFrames: sameFormat && Self.multiFrameFormats.contains(request.target.id),
                               progress: progress)
        }

        try Self.write(bytes, to: destination, force: options.force)
        progress(1.0)
        return ConversionResult(outputs: [destination], bytesWritten: bytes.count)
    }

    private func encode(
        source: CGImageSource,
        request: ConversionRequest,
        targetType: UTType,
        keepAllFrames: Bool,
        progress: @Sendable (Double) -> Void
    ) throws -> Data {
        let options = request.options
        let frameCount = keepAllFrames ? CGImageSourceGetCount(source) : 1
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, targetType.identifier as CFString, frameCount, nil) else {
            throw WedgeError.toolFailed(tool: id, code: 1, message: "No encoder for \(request.target.id)")
        }
        if keepAllFrames, !options.stripMetadata,
           let fileProps = CGImageSourceCopyProperties(source, nil) as? [CFString: Any],
           let gif = fileProps[kCGImagePropertyGIFDictionary] {
            CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: gif] as CFDictionary)
        }

        for index in 0..<frameCount {
            guard var image = Self.loadFrame(source, index: index, maxDimension: options.maxDimension) else {
                throw WedgeError.invalidInput("Cannot decode image: \(request.input.lastPathComponent)")
            }
            if Self.opaqueFormats.contains(request.target.id) && Self.hasAlpha(image) {
                image = try Self.flattenOnWhite(image)
            }
            let sourceProps = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] ?? [:]
            var props: [CFString: Any] = [:]
            if options.stripMetadata {
                // Orientation is not private data and dropping it would visibly rotate the image.
                if let o = sourceProps[kCGImagePropertyOrientation] { props[kCGImagePropertyOrientation] = o }
            } else {
                for key in Self.metadataKeys { if let v = sourceProps[key] { props[key] = v } }
            }
            if let q = options.quality, request.target.id == "jpeg" || request.target.id == "heic" {
                props[kCGImageDestinationLossyCompressionQuality] = q
            }
            CGImageDestinationAddImage(dest, image, props as CFDictionary)
            progress(0.1 + 0.7 * Double(index + 1) / Double(frameCount))
        }
        guard CGImageDestinationFinalize(dest) else {
            throw WedgeError.toolFailed(tool: id, code: 1, message: "Encoding to \(request.target.id) failed")
        }
        return data as Data
    }

    /// Decodes one frame. Downscaling goes through ImageIO's thumbnailer, which keeps the
    /// source color profile. No orientation transform is applied: the tag is carried instead.
    private static func loadFrame(_ source: CGImageSource, index: Int, maxDimension: Int?) -> CGImage? {
        guard let full = CGImageSourceCreateImageAtIndex(source, index, nil) else { return nil }
        guard let maxDim = maxDimension, max(full.width, full.height) > maxDim else { return full }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDim,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, index, opts as CFDictionary)
    }

    /// Writes `data` to a temporary file beside `destination`, then moves it into place, so
    /// the destination (which may be the input itself under `force`) is never left half-written.
    static func write(_ data: Data, to destination: URL, force: Bool) throws {
        let fm = FileManager.default
        if !force && fm.fileExists(atPath: destination.path) { throw WedgeError.outputExists(destination) }
        let tmp = destination.deletingLastPathComponent()
            .appendingPathComponent(".wedge-\(UUID().uuidString).tmp")
        try data.write(to: tmp)
        defer { try? fm.removeItem(at: tmp) }
        if force {
            if fm.fileExists(atPath: destination.path) {
                _ = try fm.replaceItemAt(destination, withItemAt: tmp)
            } else {
                try fm.moveItem(at: tmp, to: destination)
            }
        } else {
            do {
                try fm.moveItem(at: tmp, to: destination)
            } catch let error as CocoaError where error.code == .fileWriteFileExists {
                throw WedgeError.outputExists(destination)
            }
        }
    }

    private static func hasAlpha(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return false
        default: return true
        }
    }

    private static func flattenOnWhite(_ image: CGImage) throws -> CGImage {
        let width = image.width, height = image.height
        let own = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
        let ctx = [own, CGColorSpace(name: CGColorSpace.sRGB)].lazy.compactMap { $0 }.compactMap {
            CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                      space: $0, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        }.first
        guard let ctx else {
            throw WedgeError.toolFailed(tool: "image.imageio", code: 1, message: "Cannot allocate drawing context")
        }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let out = ctx.makeImage() else {
            throw WedgeError.toolFailed(tool: "image.imageio", code: 1, message: "Flatten failed")
        }
        return out
    }
}
