import Foundation
import Testing
import UniformTypeIdentifiers
@testable import WedgeApp

@MainActor
@Suite struct DropHandlingTests {
    private func fileProvider(_ url: URL) -> NSItemProvider {
        NSItemProvider(item: url as NSURL, typeIdentifier: UTType.fileURL.identifier)
    }

    @Test func fileURLProvidersYieldTheirURLsInOrder() async {
        let a = URL(fileURLWithPath: "/tmp/a.png")
        let b = URL(fileURLWithPath: "/tmp/b.pdf")
        let urls = await DropHandler.urls(from: [fileProvider(a), fileProvider(b)])
        #expect(urls == [a, b])
    }

    @Test func fileURLDeliveredAsDataIsDecoded() async {
        let a = URL(fileURLWithPath: "/tmp/a.png")
        let provider = NSItemProvider(item: a.dataRepresentation as NSData, typeIdentifier: UTType.fileURL.identifier)
        #expect(await DropHandler.urls(from: [provider]) == [a])
    }

    @Test func nonFileProvidersAreIgnored() async {
        let text = NSItemProvider(object: "hello" as NSString)
        let web = NSItemProvider(item: URL(string: "https://example.com/x.png")! as NSURL, typeIdentifier: UTType.url.identifier)
        #expect(await DropHandler.urls(from: [text, web]).isEmpty)
    }

    @Test func mixedProvidersYieldOnlyFileURLs() async {
        let a = URL(fileURLWithPath: "/tmp/a.png")
        let text = NSItemProvider(object: "hello" as NSString)
        let urls = await DropHandler.urls(from: [text, fileProvider(a)])
        #expect(urls == [a])
    }

    @Test func noProvidersYieldNothing() async {
        #expect(await DropHandler.urls(from: []).isEmpty)
    }
}
