import Foundation

public struct ConversionProgress: Sendable {
    public let request: ConversionRequest
    public let fraction: Double

    public init(request: ConversionRequest, fraction: Double) {
        self.request = request
        self.fraction = fraction
    }
}

/// Runs conversions against a registry: single, or batch with a concurrency cap and cancellation.
public final class ConversionService: Sendable {
    private let registry: ConverterRegistry

    public init(registry: ConverterRegistry) {
        self.registry = registry
    }

    public func convert(
        _ request: ConversionRequest,
        progress: @Sendable (Double) -> Void = { _ in }
    ) async throws -> ConversionResult {
        guard FileManager.default.fileExists(atPath: request.input.path) else {
            throw WedgeError.inputNotFound(request.input)
        }
        let from = FileFormat.format(forExtension: request.input.pathExtension)
        guard let from, let converter = registry.converter(from: from, to: request.target) else {
            throw WedgeError.unsupportedConversion(
                from: from?.id ?? request.input.pathExtension.lowercased(),
                to: request.target.id)
        }
        return try await converter.convert(request, progress: progress)
    }

    /// Converts every request, at most `maxConcurrent` at a time. Results are returned in
    /// request order. Once the surrounding task is cancelled no new work starts, and every
    /// item that did not complete is reported as `WedgeError.cancelled`.
    public func convertBatch(
        _ requests: [ConversionRequest],
        maxConcurrent: Int = 4,
        progress: @Sendable (ConversionProgress) -> Void = { _ in }
    ) async -> [Result<ConversionResult, Error>] {
        let cap = max(1, maxConcurrent)
        return await withoutActuallyEscaping(progress) { progress in
            var results = [Result<ConversionResult, Error>?](repeating: nil, count: requests.count)
            await withTaskGroup(of: (Int, Result<ConversionResult, Error>).self) { group in
                var running = 0
                for (index, request) in requests.enumerated() {
                    if running >= cap, let (i, r) = await group.next() {
                        results[i] = r
                        running -= 1
                    }
                    if Task.isCancelled { break }
                    running += 1
                    group.addTask {
                        do {
                            let result = try await self.convert(request) {
                                progress(ConversionProgress(request: request, fraction: $0))
                            }
                            return (index, .success(result))
                        } catch is CancellationError {
                            return (index, .failure(WedgeError.cancelled))
                        } catch {
                            return (index, .failure(error))
                        }
                    }
                }
                for await (i, r) in group { results[i] = r }
            }
            return results.map { $0 ?? .failure(WedgeError.cancelled) }
        }
    }
}
