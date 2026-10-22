import Foundation
import WedgeCore

@MainActor
final class ConversionModel: ObservableObject {
    struct Item: Identifiable {
        let id: UUID
        let url: URL
        var state: ItemState
    }

    enum ItemState: Equatable {
        case pending
        case running(Double)
        case done([URL])
        case failed(String)
    }

    @Published private(set) var items: [Item] = []
    @Published private(set) var isConverting = false

    private let service: ConversionService
    private var task: Task<[Result<ConversionResult, Error>], Never>?

    init(service: ConversionService = ConversionService(registry: Wedge.defaultRegistry())) {
        self.service = service
    }

    func add(_ urls: [URL]) {
        for url in urls {
            let standardized = url.standardizedFileURL
            guard !items.contains(where: { $0.url == standardized }) else { continue }
            items.append(Item(id: UUID(), url: standardized, state: .pending))
        }
    }

    func clear() {
        guard !isConverting else { return }
        items.removeAll()
    }

    /// Targets valid for every input; empty for no inputs or when any input has none.
    func availableTargets(for urls: [URL]) -> [FileFormat] {
        guard let first = urls.first else { return [] }
        var common = service.availableTargets(for: first)
        for url in urls.dropFirst() {
            let targets = Set(service.availableTargets(for: url))
            common.removeAll { !targets.contains($0) }
        }
        return common
    }

    /// Converts the pending and failed items; finished items are left alone.
    /// A call while a run is in flight does nothing.
    func convert(to target: FileFormat, options: ConversionOptions, outputDirectory: URL? = nil) async {
        guard !isConverting else { return }
        let indices = items.indices.filter {
            switch items[$0].state {
            case .pending, .failed: true
            case .running, .done: false
            }
        }
        guard !indices.isEmpty else { return }

        let ids = indices.map { items[$0].id }
        let requests = indices.map {
            ConversionRequest(input: items[$0].url, target: target, outputDirectory: outputDirectory, options: options)
        }
        let idByInput = Dictionary(uniqueKeysWithValues: zip(requests.map(\.input), ids))
        for id in ids { setState(.running(0), for: id) }
        isConverting = true

        let service = service
        let batch = Task {
            await service.convertBatch(requests) { [weak self] update in
                guard let id = idByInput[update.request.input] else { return }
                Task { @MainActor in self?.applyProgress(update.fraction, for: id) }
            }
        }
        task = batch
        let results = await withTaskCancellationHandler { await batch.value } onCancel: { batch.cancel() }
        task = nil

        for (id, result) in zip(ids, results) {
            switch result {
            case .success(let value): setState(.done(value.outputs), for: id)
            case .failure(let error): setState(.failed(Self.message(for: error)), for: id)
            }
        }
        isConverting = false
    }

    func cancel() {
        task?.cancel()
    }

    private func applyProgress(_ fraction: Double, for id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }), case .running = items[index].state else { return }
        items[index].state = .running(fraction)
    }

    private func setState(_ state: ItemState, for id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].state = state
    }

    private static func message(for error: Error) -> String {
        guard let error = error as? WedgeError else { return error.localizedDescription }
        switch error {
        case .inputNotFound(let url): return "Input not found: \(url.lastPathComponent)"
        case .unsupportedConversion(let from, let to): return "Can't convert \(from) to \(to)"
        case .outputExists(let url): return "Output already exists: \(url.lastPathComponent)"
        case .resourceLimitExceeded(let detail): return "Resource limit exceeded: \(detail)"
        case .toolFailed(let tool, _, let message): return "\(tool) failed: \(message)"
        case .toolNotInstalled(let tool, let hint): return "\(tool) is not installed (\(hint))"
        case .cancelled: return "Cancelled"
        case .invalidInput(let detail): return "Invalid input: \(detail)"
        }
    }
}
