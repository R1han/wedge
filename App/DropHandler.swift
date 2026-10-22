import Foundation
import UniformTypeIdentifiers

enum DropHandler {
    /// File URLs carried by the dropped providers, in drop order. Providers that are not file URLs are ignored.
    @MainActor
    static func urls(from providers: [NSItemProvider]) async -> [URL] {
        var urls: [URL] = []
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            if let url = await fileURL(from: provider) { urls.append(url) }
        }
        return urls
    }

    @MainActor
    private static func fileURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url: URL?
                switch item {
                case let value as URL: url = value
                case let data as Data: url = URL(dataRepresentation: data, relativeTo: nil)
                default: url = nil
                }
                continuation.resume(returning: url?.isFileURL == true ? url : nil)
            }
        }
    }
}
