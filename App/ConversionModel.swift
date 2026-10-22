import Foundation
import os
import WedgeCore

@MainActor
final class ConversionModel: ObservableObject {
    struct Item: Identifiable {
        let id: UUID
        let url: URL
        var state: ItemState

        var isConvertible: Bool {
            if case .unsupported = state { return false }
            return true
        }
    }

    enum ItemState: Equatable {
        case pending
        case running(Double)
        case done([URL], FileFormat)
        case failed(String)
        case cancelled
        /// No target exists for this file (missing, or a type Wedge cannot convert); never part of a run.
        case unsupported(String)
    }

    @Published private(set) var items: [Item] = []
    @Published private(set) var isConverting = false
    /// Targets valid for every convertible item; empty when there are none or they share no target.
    @Published private(set) var targets: [FileFormat] = []

    private let service: ConversionService
    @Published private(set) var notice: String?

    private var itemTargets: [UUID: [FileFormat]] = [:]
    private var task: Task<[Result<ConversionResult, Error>], Never>?

    private static let log = Logger(subsystem: "com.r1han.wedge", category: "conversion")
    private static let maxMessageLength = 200

    init(service: ConversionService = ConversionService(registry: Wedge.defaultRegistry())) {
        self.service = service
    }

    /// Adds files as pending items. A file already in the list is not duplicated; if it was
    /// finished (done, failed or cancelled) it goes back to pending so it can be converted again.
    func add(_ urls: [URL]) {
        for url in urls {
            let normalized = url.resolvingSymlinksInPath().standardizedFileURL
            if let index = items.firstIndex(where: { $0.url == normalized }) {
                switch items[index].state {
                case .done, .failed, .cancelled: items[index].state = .pending
                case .unsupported: classify(index)
                case .pending, .running: break
                }
            } else {
                items.append(Item(id: UUID(), url: normalized, state: .pending))
                classify(items.count - 1)
            }
        }
        refreshTargets()
    }

    /// Adds the result of a drop. A drop with no file URLs leaves a notice that the next successful add clears.
    func addDropped(_ urls: [URL]) {
        guard !urls.isEmpty else {
            notice = "Only files and folders can be added"
            return
        }
        notice = nil
        add(urls)
    }

    func clear() {
        guard !isConverting else { return }
        items.removeAll()
        itemTargets.removeAll()
        refreshTargets()
    }

    func remove(_ id: UUID) {
        guard !isConverting, let index = items.firstIndex(where: { $0.id == id }) else { return }
        items.remove(at: index)
        itemTargets[id] = nil
        refreshTargets()
    }

    /// Whether `convert(to:)` would have anything to do for this target.
    func hasWork(for target: FileFormat) -> Bool {
        !isConverting && !eligibleIndices(for: target).isEmpty
    }

    /// Converts the items that still need it: pending, failed and cancelled ones, and done ones
    /// whose last conversion was to a different target. A call while a run is in flight does nothing.
    func convert(to target: FileFormat, options: ConversionOptions, outputDirectory: URL? = nil) async {
        guard !isConverting else { return }
        let indices = eligibleIndices(for: target)
        guard !indices.isEmpty else { return }

        let ids = indices.map { items[$0].id }
        let requests = indices.map {
            ConversionRequest(input: items[$0].url, target: target, outputDirectory: outputDirectory, options: options)
        }
        let idByInput = Dictionary(zip(requests.map(\.input), ids), uniquingKeysWith: { first, _ in first })
        for id in ids { setState(.running(0), for: id) }
        isConverting = true

        let service = service
        let batch = Task {
            await service.convertBatch(
                requests,
                progress: { [weak self] update in
                    guard let id = idByInput[update.request.input] else { return }
                    Task { @MainActor in self?.applyProgress(update.fraction, for: id) }
                },
                onItemFinished: { [weak self] index, result in
                    let id = ids[index]
                    Task { @MainActor in self?.finishIfRunning(id, result, target: target) }
                }
            )
        }
        task = batch
        let results = await withTaskCancellationHandler { await batch.value } onCancel: { batch.cancel() }
        task = nil

        for (id, result) in zip(ids, results) { finish(id, result, target: target) }
        isConverting = false
    }

    func cancel() {
        task?.cancel()
    }

    static func message(for error: Error) -> String {
        guard let error = error as? WedgeError else { return error.localizedDescription }
        switch error {
        case .inputNotFound(let url): return "Input not found: \(url.lastPathComponent)"
        case .unsupportedConversion(let from, let to): return "Can't convert \(from) to \(to)"
        case .outputExists(let url): return "Output already exists: \(url.lastPathComponent)"
        case .resourceLimitExceeded(let detail): return "Resource limit exceeded: \(detail)"
        case .toolFailed(let tool, let code, let message):
            log.error("\(tool, privacy: .public) failed (exit \(code)): \(message, privacy: .private)")
            return "\(tool) failed: \(summary(of: message))"
        case .toolNotInstalled(let tool, let hint): return "\(tool) is not installed (\(hint))"
        case .cancelled: return "Cancelled"
        case .invalidInput(let detail): return "Invalid input: \(detail)"
        }
    }

    /// First non-empty line of tool output, truncated for display.
    private static func summary(of text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        guard line.count > maxMessageLength else { return line }
        return line.prefix(maxMessageLength) + "\u{2026}"
    }

    private func eligibleIndices(for target: FileFormat) -> [Int] {
        items.indices.filter {
            switch items[$0].state {
            case .pending, .failed, .cancelled: true
            case .done(_, let last): last != target
            case .running, .unsupported: false
            }
        }
    }

    /// Looks up the item's targets and marks it unsupported when it has none.
    private func classify(_ index: Int) {
        let item = items[index]
        let available = service.availableTargets(for: item.url)
        itemTargets[item.id] = available
        if available.isEmpty {
            let exists = FileManager.default.fileExists(atPath: item.url.path)
            items[index].state = .unsupported(exists ? "Unsupported file type" : "File not found")
        } else {
            items[index].state = .pending
        }
    }

    private func refreshTargets() {
        let lists = items.filter(\.isConvertible).compactMap { itemTargets[$0.id] }
        guard var common = lists.first else {
            targets = []
            return
        }
        for available in lists.dropFirst() {
            let set = Set(available)
            common.removeAll { !set.contains($0) }
        }
        targets = common
    }

    private func applyProgress(_ fraction: Double, for id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }),
              case .running(let current) = items[index].state, fraction > current else { return }
        items[index].state = .running(fraction)
    }

    /// Late-arriving per-item callbacks must not touch an item that already moved on.
    private func finishIfRunning(_ id: UUID, _ result: Result<ConversionResult, Error>, target: FileFormat) {
        guard let index = items.firstIndex(where: { $0.id == id }), case .running = items[index].state else { return }
        finish(id, result, target: target)
    }

    private func finish(_ id: UUID, _ result: Result<ConversionResult, Error>, target: FileFormat) {
        switch result {
        case .success(let value): setState(.done(value.outputs, target), for: id)
        case .failure(let error as WedgeError) where error == .cancelled: setState(.cancelled, for: id)
        case .failure(let error): setState(.failed(Self.message(for: error)), for: id)
        }
    }

    private func setState(_ state: ItemState, for id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].state = state
    }
}
