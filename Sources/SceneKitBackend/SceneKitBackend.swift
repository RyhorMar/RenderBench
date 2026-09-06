import BenchRuntime
import Foundation

/// SceneKit backend: a 2D chart drawn as `.line`-primitive geometry inside a 3D scene, viewed
/// through an orthographic camera.
///
/// Seventh of the nine built so far, and the one whose own hypothesis is that the method is
/// wrong for the job: SceneKit's `.line` primitive rasterises at exactly one device pixel,
/// regardless of the geometry's stated width, so a stroke this project draws everywhere else at
/// 1.5 points cannot be expressed here at all. That is not a bug to work around — building the
/// stroke's own geometry would make this a Metal backend running inside a SceneKit scene rather
/// than a measurement of SceneKit's own drawing primitive — so the failure is characterised and
/// reported rather than hidden.
///
/// - SeeAlso: Docs/methods/scenekit.md
public enum SceneKitBackend {
    /// Stable identifier used in benchmark metadata and in the comparison matrix.
    public static let identifier = "scenekit"

    /// What this backend can do, as measured numbers.
    ///
    /// Empty until a device run fills it. A capability declared before it is measured is a
    /// hypothesis wearing a contract's clothes.
    public static let capabilities: [Capability] = []
}
