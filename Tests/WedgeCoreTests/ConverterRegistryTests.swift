import Foundation
import Testing
@testable import WedgeCore

private struct StubConverter: Converter {
    let id: String
    let from: FileFormat
    let to: FileFormat

    func supports(from: FileFormat, to: FileFormat) -> Bool {
        from == self.from && to == self.to
    }

    func convert(
        _ request: ConversionRequest,
        progress: @Sendable (Double) -> Void
    ) async throws -> ConversionResult {
        progress(1.0)
        return ConversionResult(outputs: [], bytesWritten: 0)
    }
}

struct ConverterRegistryTests {
    private let png = FileFormat.format(forExtension: "png")!
    private let jpeg = FileFormat.format(forExtension: "jpg")!
    private let gif = FileFormat.format(forExtension: "gif")!

    @Test func lookupFindsRegisteredConverter() {
        let registry = ConverterRegistry()
        registry.register(StubConverter(id: "stub", from: png, to: jpeg))
        #expect(registry.converter(from: png, to: jpeg)?.id == "stub")
    }

    @Test func firstMatchWins() {
        let registry = ConverterRegistry()
        registry.register(StubConverter(id: "first", from: png, to: jpeg))
        registry.register(StubConverter(id: "second", from: png, to: jpeg))
        #expect(registry.converter(from: png, to: jpeg)?.id == "first")
    }

    @Test func unsupportedPairReturnsNil() {
        let registry = ConverterRegistry()
        registry.register(StubConverter(id: "stub", from: png, to: jpeg))
        #expect(registry.converter(from: jpeg, to: png) == nil)
        #expect(ConverterRegistry().converter(from: png, to: jpeg) == nil)
    }

    @Test func pairsListsSupportedAndSorted() {
        let registry = ConverterRegistry()
        registry.register(StubConverter(id: "b", from: png, to: jpeg))
        registry.register(StubConverter(id: "a", from: gif, to: png))
        registry.register(StubConverter(id: "dup", from: png, to: jpeg))
        let pairs = registry.pairs().map { "\($0.from.id)->\($0.to.id)" }
        #expect(pairs == ["gif->png", "png->jpeg"])
    }
}
