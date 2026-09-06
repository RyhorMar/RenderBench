import BenchRuntime
import Foundation

/// Metal compute backend: the only one of the nine whose method is the reduction itself.
///
/// Every other backend receives a `PreparedFrame` already reduced by `BenchDownsampling` on the
/// CPU and draws it. This one asks the scene to skip that step — `RendererDescriptor.reducesOnGPU`
/// tells it to — and receives every windowed point instead, unreduced. `encode(_:)` buckets each
/// series' runs by normalised x, finds the minimum and maximum of each bucket on the GPU, reads
/// the result back, and only then draws with the same instanced-quad line pass `MetalBackend`
/// uses. The hypothesis under test: does moving MinMax reduction onto the GPU change the picture.
public enum MetalComputeBackend {
    /// Stable identifier used in benchmark metadata and in the comparison matrix.
    public static let identifier = "metal-compute"

    /// What this backend can do, as measured numbers.
    ///
    /// Empty until a device run fills it — see the other eight backends' own empty tables for the
    /// same reason: no measurement has been taken on a device yet.
    public static let capabilities: [Capability] = []
}
