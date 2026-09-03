import BenchRuntime
import Foundation

/// Metal backend: points uploaded once per frame, expanded into triangles on the GPU.
///
/// Third of the nine, and the first whose rasterisation is measurable rather than inferred. The
/// two Core Graphics backends can report what their CPU did and nothing about what turned that
/// into pixels; a command buffer carries its own start and end timestamps, so this one fills the
/// `gpu` column that has been empty since the schema was written.
///
/// What it is expected to cost, stated before the measurement so the measurement can refute it:
/// the CPU should fall to an upload and a handful of draw calls, and the frame should become a
/// question about fill rate rather than about path construction. If that does not happen, the
/// interesting result is why.
public enum MetalBackend {
    /// Stable identifier used in benchmark metadata and in the comparison matrix.
    public static let identifier = "metal"

    /// What this backend can do, as measured numbers.
    ///
    /// Empty until a device run fills it. The simulator reports a GPU named
    /// `Apple iOS simulator GPU` in family `apple1`, and its timings describe the host's
    /// translation layer rather than any phone.
    public static let capabilities: [Capability] = []
}
