/// Everything this package reports as a failure rather than a crash.
///
/// The split is deliberate: a programmer error traps, a condition arising from data or from the
/// device is thrown. A renderer must never take the host application down because a shader would
/// not compile or because a series arrived in the wrong unit.
public enum ChartError: Error, Sendable, Equatable {
    /// Downsampling was asked to average a quantity that must not be averaged — API gravity, a
    /// ratio on mass, anything whose mean is not the mean of the thing it describes.
    case nonAveragable(unit: Unit)

    /// A scale was built over a domain with no extent, so no projection is defined.
    case emptyDomain

    /// A conversion was requested between units measuring different quantities.
    case incompatibleUnits(from: Unit, to: Unit)

    /// A shader failed to build. `message` rather than the underlying error because this type is
    /// `Sendable` and `any Error` is not; the text is what a caller can log or display anyway.
    case shaderCompilation(function: String, message: String)

    /// The backend does not implement this chart kind. Reported, never faked: a backend that
    /// draws something approximate here would corrupt every comparison the project publishes.
    case unsupported(kind: String, by: String)

    /// A buffer allocation exceeded the budget the caller set, in bytes.
    case outOfMemory(requested: Int, budget: Int)
}
