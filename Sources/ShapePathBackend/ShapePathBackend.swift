import BenchRuntime
import Foundation

/// Shape/Path backend: one retained SwiftUI `Shape` per series.
///
/// Fifth of the nine, and the first retained-mode backend built from `Shape` rather than from a
/// layer tree (`CoreAnimationBackend`) or an immediate-mode closure (`CanvasBackend`). A `Path` is
/// built once per series in `encode(_:)`; SwiftUI owns the value from there and decides for itself
/// when to turn it into pixels, on its own render server, the same shape of problem
/// `CoreAnimationRenderer` and `SwiftChartsRenderer` both have.
public enum ShapePathBackend {
    /// Stable identifier used in benchmark metadata and in the comparison matrix.
    public static let identifier = "shape-path"

    /// What this backend can do, as measured numbers.
    ///
    /// Empty until a device run fills it. A capability declared before it is measured is a
    /// hypothesis wearing a contract's clothes.
    public static let capabilities: [Capability] = []
}
