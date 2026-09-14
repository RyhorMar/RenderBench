import BenchRuntime
import Foundation

/// Core Image backend: a raster built exactly the way ``CoreGraphicsReference`` builds it,
/// delivered to the screen through a `CIColorControls` render on the GPU.
///
/// Sixth of the nine, and the first that does not construct the line at all. Every backend before
/// it turns geometry into pixels itself; this one hands `CoreGraphicsReference`'s already-finished
/// pixels — the same CPU rasterisation every Core-Graphics-based backend in this project is
/// compared against — to a Core Image filter pipeline, and measures what delivering an
/// already-drawn raster costs, not what drawing a line costs.
///
/// - SeeAlso: Docs/methods/core-image.md
public enum CoreImageBackend {
    /// Stable identifier used in benchmark metadata and in the results files.
    public static let identifier = "core-image"

    /// What this backend can do, as measured numbers.
    ///
    /// Empty until a device run fills it. A capability declared before it is measured is a
    /// hypothesis wearing a contract's clothes.
    public static let capabilities: [Capability] = []
}
