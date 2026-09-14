import BenchRuntime
import Foundation

/// Core Animation backend: one `CAShapeLayer` per series, geometry rebuilt each frame.
///
/// Second of the nine, and the first real comparison the project can make. What it is expected to
/// cost is stated in advance so the measurement can confirm or refute it: rebuilding a `CGPath`
/// every frame, plus the layer tree's own bookkeeping on commit. Where Canvas pays for immediate
/// drawing, this pays for retained geometry it then has to invalidate.
///
/// **It does not own a display link.** The method is named "CAShapeLayer + CADisplayLink" in the
/// design notes, and the second half is deliberately not implemented: one tick per scene is an
/// invariant of this project, and a backend running its own clock would be drawing different work
/// from the one it is compared against. The clock stays shared; only the geometry differs.
public enum CoreAnimationBackend {
    /// Stable identifier used in benchmark metadata and in the results files.
    public static let identifier = "core-animation"

    /// What this backend can do, as measured numbers.
    ///
    /// Empty until a device run fills it. A capability declared before it is measured is a
    /// hypothesis wearing a contract's clothes.
    public static let capabilities: [Capability] = []
}
