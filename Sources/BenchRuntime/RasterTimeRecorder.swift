import Foundation
import Synchronization

/// Carries a rasterisation time out of a draw callback, to be collected on the next frame.
///
/// The measurement it exists for is the one the project was missing: for an immediate-mode backend
/// the drawing happens inside a closure the view layer calls during its own render pass, long after
/// the code that prepared the frame has returned. Timing only what the preparation did — which is
/// what this package published until now — reports path construction as the cost of a rendering
/// method and omits the rendering.
///
/// A one-deep slot rather than a callback, for the same reason the frame slot is one: writing
/// observable state from inside a draw pass is how a render loop starts driving itself. The value
/// is left here and picked up on the next tick, one frame late, which is stated rather than hidden.
public final class RasterTimeRecorder: Sendable {
    private let latest = Mutex<UInt64?>(nil)

    public init() {}

    /// Records the time a draw pass took, in nanoseconds. Safe to call from a draw callback.
    public func record(nanoseconds: UInt64) {
        latest.withLock { $0 = nanoseconds }
    }

    /// Takes the most recent recording, if one has arrived since the last call.
    ///
    /// Returns `nil` when no draw has happened — which is the honest answer for a frame that was
    /// prepared and never presented, and must not be reported as zero.
    public func take() -> UInt64? {
        latest.withLock { value in
            defer { value = nil }
            return value
        }
    }
}
