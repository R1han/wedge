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

    /// Property entries worth carrying across when metadata is kept.
    private static var metadataKeys: [CFString] { [
        kCGImagePropertyExifDictionary, kCGImagePropertyTIFFDictionary, kCGImagePropertyGPSDictionary,
        kCGImagePropertyIPTCDictionary, kCGImagePropertyOrientation,
        kCGImagePropertyDPIWidth, kCGImagePropertyDPIHeight,
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
              CGImageSourceGetCount(source) > 0,
              var image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw WedgeError.invalidInput("Cannot decode image: \(request.input.lastPathComponent)")
        }
        let sourceProps = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        progress(0.3)

        var targetWidth = image.width
        var targetHeight = image.height
        if let maxDim = options.maxDimension, max(image.width, image.height) > maxDim {
            let scale = Double(maxDim) / Double(max(image.width, image.height))
            targetWidth = max(1, Int((Double(image.width) * scale).rounded()))
            targetHeight = max(1, Int((Double(image.height) * scale).rounded()))
        }
        let flatten = Self.opaqueFormats.contains(request.target.id) && Self.hasAlpha(image)
        if targetWidth != image.width || targetHeight != image.height || flatten {
            image = try Self.redraw(image, width: targetWidth, height: targetHeight, flattenOnWhite: flatten)
        }
        progress(0.6)

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

        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, targetType.identifier as CFString, 1, nil) else {
            throw WedgeError.toolFailed(tool: id, code: 1, message: "No encoder for \(request.target.id)")
        }
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            throw WedgeError.toolFailed(tool: id, code: 1, message: "Encoding to \(request.target.id) failed")
        }
        progress(0.9)

        if let dir = request.outputDirectory {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let destination = OutputNamer().destination(
            forInput: request.input, target: request.target,
            in: request.outputDirectory, force: options.force)
        let bytes = data as Data
        if options.force {
            try bytes.write(to: destination, options: .atomic)
        } else {
            // Re-check right before writing; `.withoutOverwriting` closes the remaining race.
            guard !fm.fileExists(atPath: destination.path) else { throw WedgeError.outputExists(destination) }
            do {
                try bytes.write(to: destination, options: .withoutOverwriting)
            } catch let error as CocoaError where error.code == .fileWriteFileExists {
                throw WedgeError.outputExists(destination)
            }
        }
        progress(1.0)
        return ConversionResult(outputs: [destination], bytesWritten: bytes.count)
    }

    private static func hasAlpha(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return false
        default: return true
        }
    }

    private static func redraw(_ image: CGImage, width: Int, height: Int, flattenOnWhite: Bool) throws -> CGImage {
        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else {
            throw WedgeError.toolFailed(tool: "image.imageio", code: 1, message: "Cannot allocate drawing context")
        }
        ctx.interpolationQuality = .high
        if flattenOnWhite {
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let out = ctx.makeImage() else {
            throw WedgeError.toolFailed(tool: "image.imageio", code: 1, message: "Resize failed")
        }
        return out
    }
}
