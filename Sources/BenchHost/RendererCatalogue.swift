/// The list a picker or a navigation screen is built from.
public struct RendererEntry: Identifiable, Sendable {
    /// The renderer's identifier, mirrored from `descriptor` for `Identifiable` conformance.
    public var id: String { descriptor.identifier }
    /// Identity and capability facts for the wrapped renderer.
    public let descriptor: RendererDescriptor
    /// Builds a fresh renderer instance. A screen calls this once, on appearance; it is not a
    /// cache, so calling it twice must never hand back the same instance.
    public let make: @MainActor @Sendable () -> any ChartRenderer

    /// Wraps one conformer's static descriptor and its initialiser behind a single value a list
    /// can hold without naming the concrete type.
    public init<R: ChartRenderer>(_ type: R.Type) {
        descriptor = R.descriptor
        make = { R.init() }
    }
}
