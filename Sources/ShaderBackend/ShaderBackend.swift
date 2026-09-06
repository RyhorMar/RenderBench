import BenchRuntime
import Foundation

/// Shader backend: SwiftUI's `colorEffect`, run once per pixel.
///
/// Eighth of the nine, and the first whose drawing primitive is neither a shape, a layer nor a
/// vertex buffer, but a per-pixel program: for every pixel a `Rectangle().colorEffect` composites,
/// the shader `chart_line` — compiled by Xcode into the demo's own bundle, since SwiftPM has no
/// path to compile a `.metal` file at all, let alone one `ShaderLibrary.default` can find — measures
/// that pixel's distance to every segment of one contiguous run and turns the result into coverage
/// analytically, with no rasterised geometry standing between the data and the pixel. The card's
/// hypothesis, stated before anything is measured: this method works over the raster, not over the
/// data, so the line the reader sees was decided by a program running once per output pixel rather
/// than by anything this backend built in advance.
public enum ShaderBackend {
    /// Stable identifier used in benchmark metadata and in the comparison matrix.
    public static let identifier = "shader"

    /// What this backend can do, as measured numbers.
    ///
    /// Empty until a device run fills it. A capability declared before it is measured is a
    /// hypothesis wearing a contract's clothes.
    public static let capabilities: [Capability] = []
}
