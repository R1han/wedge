import Foundation

public struct ConversionOptions: Sendable {
    public var quality: Double?
    public var maxDimension: Int?
    public var stripMetadata: Bool
    public var force: Bool
    public var extra: [String: String]

    public init(
        quality: Double? = nil,
        maxDimension: Int? = nil,
        stripMetadata: Bool = false,
        force: Bool = false,
        extra: [String: String] = [:]
    ) {
        self.quality = quality
        self.maxDimension = maxDimension
        self.stripMetadata = stripMetadata
        self.force = force
        self.extra = extra
    }
}

public struct ConversionRequest: Sendable {
    public let input: URL
    public let target: FileFormat
    public let outputDirectory: URL?
    public let options: ConversionOptions

    public init(
        input: URL,
        target: FileFormat,
        outputDirectory: URL? = nil,
        options: ConversionOptions = ConversionOptions()
    ) {
        self.input = input
        self.target = target
        self.outputDirectory = outputDirectory
        self.options = options
    }
}

public struct ConversionResult: Sendable {
    public let outputs: [URL]
    public let bytesWritten: Int

    public init(outputs: [URL], bytesWritten: Int) {
        self.outputs = outputs
        self.bytesWritten = bytesWritten
    }
}
