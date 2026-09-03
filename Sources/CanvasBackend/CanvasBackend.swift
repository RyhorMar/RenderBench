import Foundation

/// SwiftUI `Canvas` backend: the CPU reference path.
///
/// First of the nine backends, and the one the others are checked against, because it is the
/// easiest to reason about and the easiest to prove correct. Its limits are expected to be the
/// lowest of the set; establishing where they actually fall is the point of measuring it.
///
/// The drawing implementation lands with the host application — a backend with nowhere to draw
/// cannot be verified, and an unverified renderer is not worth committing.
public enum CanvasBackend {
    /// Stable identifier used in benchmark metadata and in the comparison matrix.
    public static let identifier = "canvas"
}
