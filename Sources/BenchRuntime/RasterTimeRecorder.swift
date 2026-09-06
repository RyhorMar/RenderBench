import Foundation
import Synchronization

/// A nanosecond timing paired with the encode it measures.
///
/// A ring of several frames in flight — Metal's `inFlightFrames` — can finish out of order, so a
/// reading needs to carry its own frame number rather than borrow whatever revision is current
/// when it happens to be collected. Without it, a raster reading and a GPU reading picked up on
/// the same tick can silently describe two different frames, and summing them reports a total for
/// a frame that never existed.
public struct RasterTimeReading: Sendable, Equatable {
    /// Time the measured pass took, in nanoseconds.
    public var nanoseconds: UInt64
    /// `ChartRenderer.encodedRevision` as of the `encode()` call that produced this reading.
    public var encodedRevision: UInt64

    public init(nanoseconds: UInt64, encodedRevision: UInt64) {
        self.nanoseconds = nanoseconds
        self.encodedRevision = encodedRevision
    }
}

/// Carries a rasterisation time out of a draw callback, to be collected on the next frame.
///
/// The measurement it exists for is the one the project was missing: for an immediate-mode backend
/// the drawing happens inside a closure the view layer calls during its own render pass, long after
/// the code that prepared the frame has returned. Timing only what the preparation did — which is
/// what this package published until now — reports path construction as the cost of a rendering
/// method and omits the rendering.
///
/// The GPU backend uses a second instance for the same shape of problem: a command buffer's start
/// and end timestamps exist only once the GPU has finished with it, which is after the frame that
/// submitted it has returned.
///
/// A one-deep slot rather than a callback, for the same reason the frame slot is one: writing
/// observable state from inside a draw pass is how a render loop starts driving itself. The value
/// is left here and picked up on the next tick, one frame late, which is stated rather than hidden.
public final class RasterTimeRecorder: Sendable {
    private let latest = Mutex<RasterTimeReading?>(nil)

    public init() {}

    /// Records the time a draw pass took, in nanoseconds, tagged with the frame it belongs to.
    /// Safe to call from a draw callback.
    public func record(nanoseconds: UInt64, encodedRevision: UInt64) {
        latest.withLock { $0 = RasterTimeReading(nanoseconds: nanoseconds, encodedRevision: encodedRevision) }
    }

    /// Takes the most recent recording, if one has arrived since the last call.
    ///
    /// Returns `nil` when no draw has happened — which is the honest answer for a frame that was
    /// prepared and never presented, and must not be reported as zero.
    public func take() -> RasterTimeReading? {
        latest.withLock { value in
            defer { value = nil }
            return value
        }
    }
}
