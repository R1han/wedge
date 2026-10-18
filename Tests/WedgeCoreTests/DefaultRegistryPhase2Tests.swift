import Testing
@testable import WedgeCore

struct DefaultRegistryPhase2Tests {
    private let md = FileFormat.format(forExtension: "md")!
    private let html = FileFormat.format(forExtension: "html")!
    private let pdf = FileFormat.format(forExtension: "pdf")!
    private let png = FileFormat.format(forExtension: "png")!

    @Test func resolvesPhase2Converters() {
        let registry = Wedge.defaultRegistry()
        #expect(registry.converter(from: md, to: html)?.id == "doc.pandoc")
        #expect(registry.converter(from: pdf, to: png)?.id == "pdf.pdfkit")
    }

    @Test func pairsIncludePhase2() {
        let ids = Wedge.defaultRegistry().pairs().map { "\($0.from.id) -> \($0.to.id)" }
        #expect(ids.contains("md -> html"))
        #expect(ids.contains("pdf -> png"))
    }
}
