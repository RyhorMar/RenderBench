import BenchHost
import CanvasBackend
import CoreAnimationBackend
import CoreImageBackend
import MetalBackend
import SceneKitBackend
import ShaderBackend
import ShapePathBackend
import SwiftChartsBackend

/// The backends this screen can switch between.
///
/// One list, built once: a picker walks it to build its rows, and ``ChartScene`` walks it to
/// resolve the entry a picker selection named back into something it can construct.
///
/// `@MainActor`: building an entry reads its conformer's `descriptor`, a requirement of a
/// main-actor protocol, so nothing that constructs one can be isolated any other way.
@MainActor
enum Catalogue {
    static let renderers: [RendererEntry] = [
        RendererEntry(CanvasRenderer.self),
        RendererEntry(CoreAnimationRenderer.self),
        RendererEntry(MetalRenderer.self),
        RendererEntry(SwiftChartsRenderer.self),
        RendererEntry(ShapePathRenderer.self),
        RendererEntry(CoreImageRenderer.self),
        RendererEntry(SceneKitRenderer.self),
        RendererEntry(ShaderRenderer.self),
    ]
}
