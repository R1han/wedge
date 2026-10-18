import Foundation

public enum Wedge {
    /// The registry with every built-in converter registered.
    public static func defaultRegistry() -> ConverterRegistry {
        let registry = ConverterRegistry()
        registry.register(ImageConverter())
        registry.register(ArchiveConverter())
        registry.register(PandocConverter())
        registry.register(MediaConverter())
        registry.register(PDFConverter())
        return registry
    }
}
