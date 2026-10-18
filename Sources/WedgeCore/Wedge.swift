import Foundation

public enum Wedge {
    /// The registry with every built-in converter registered.
    public static func defaultRegistry() -> ConverterRegistry {
        let registry = ConverterRegistry()
        registry.register(ImageConverter())
        registry.register(ArchiveConverter())
        return registry
    }
}
