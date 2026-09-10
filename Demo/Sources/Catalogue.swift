import BenchCore
import BenchHost
import CanvasBackend
import CoreAnimationBackend
import CoreImageBackend
import MetalBackend
import MetalComputeBackend
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
    /// Every backend with the rasteriser family it belongs to.
    ///
    /// The family is paired here rather than looked up by identifier so that it cannot be missing:
    /// a table keyed by id would have to hand back an optional, and an optional in this project
    /// means "this backend cannot say", which is a different claim from "nobody filled the row in".
    /// Adding a backend without stating its family does not compile.
    static let rows: [CatalogueRow] = [
        CatalogueRow(CanvasRenderer.self, family: .sharedRasteriser),
        CatalogueRow(CoreAnimationRenderer.self, family: .sharedRasteriser),
        CatalogueRow(MetalRenderer.self, family: .ownPipeline),
        CatalogueRow(SwiftChartsRenderer.self, family: .sharedRasteriser),
        CatalogueRow(ShapePathRenderer.self, family: .sharedRasteriser),
        CatalogueRow(CoreImageRenderer.self, family: .hybrid),
        CatalogueRow(SceneKitRenderer.self, family: .ownPipeline),
        CatalogueRow(ShaderRenderer.self, family: .sharedRasteriser),
        CatalogueRow(MetalComputeRenderer.self, family: .ownPipeline),
    ]

    static let renderers: [RendererEntry] = rows.map(\.entry)
}

/// One catalogue line: a backend and the rasteriser family it belongs to.
struct CatalogueRow: Identifiable, Sendable {
    /// Stored rather than read back off `entry`, which is main-actor work: `Identifiable` is not,
    /// and a conformance that crosses actors is a data race the compiler is right to refuse.
    let id: String
    let entry: RendererEntry
    let family: RasteriserFamily

    @MainActor
    init<R: ChartRenderer>(_ type: R.Type, family: RasteriserFamily) {
        entry = RendererEntry(type)
        id = entry.id
        self.family = family
    }
}
