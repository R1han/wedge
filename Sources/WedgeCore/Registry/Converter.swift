import Foundation

public protocol Converter: Sendable {
    var id: String { get }
    func supports(from: FileFormat, to: FileFormat) -> Bool
    func convert(
        _ request: ConversionRequest,
        progress: @Sendable (Double) -> Void
    ) async throws -> ConversionResult
}
