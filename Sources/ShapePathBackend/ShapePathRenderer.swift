import BenchHost
import BenchRuntime
import SwiftUI

/// `ChartRenderer` conformer for the Shape/Path backend.
///
/// Nothing here owns a device or a display link: `PolylineShape` renders through SwiftUI's own
/// render server, on its own thread, after `encode(_:)` has already returned — the same shape of
/// problem `CoreAnimationRenderer` and `SwiftChartsRenderer` both have, and the same answer
/// follows from it below.
@MainActor
@Observable
public final class ShapePathRenderer: ChartRenderer {
    /// Identity and reporting capabilities: the render server rasterises this backend's `Shape`
    /// values on its own thread, after `encode(_:)` has already returned, so neither raster nor
    /// GPU time is ever observable here.
    public static let descriptor = RendererDescriptor(
        identifier: ShapePathBackend.identifier,
        displayName: "Shape + Path",
        reportsRasterTime: false,
        reportsGPUTime: false
    )
    public static var capabilities: [Capability] { ShapePathBackend.capabilities }

    /// Last frame `encode(_:)` built. `surface` reads it, so a stalled renderer that stopped
    /// encoding would freeze on whatever is here rather than fail silently.
    private(set) var frame = ShapePathFrame()
    public private(set) var encodedRevision: UInt64 = 0
    private var tornDown = false

    public init() {}

    public func encode(_ prepared: PreparedFrame) -> EncodeReport {
        // `drawCalls` is `nil` whether torn down or active: a `Shape` handed to `.stroke(_:)`
        // becomes whatever draw commands SwiftUI's render server submits on a thread this process
        // does not observe, so that count is never something this backend has — not a shape count
        // standing in for it, and not a torn-down `0` claiming knowledge as absent as when active.
        // `pointsDrawn` differs: it is this backend's own submission count, so `0` once torn down
        // is a true report of nothing submitted, not a guess.
        guard !tornDown else { return EncodeReport(encodeNs: 0, pointsDrawn: 0, drawCalls: nil) }
        defer { encodedRevision += 1 }
        frame = ShapePathChartRenderer.encode(prepared)
        return EncodeReport(encodeNs: frame.encodeNs, pointsDrawn: frame.pointsDrawn, drawCalls: nil)
    }

    public func takeDeferredTimes() -> DeferredTimes { .none }

    public var surface: AnyView {
        AnyView(ShapePathChartView(frame: frame))
    }

    // `PolylineShape` sits inert between ticks with nothing of its own consuming compositor work
    // between frames, so there is nothing here to pause.
    public func suspend() {}
    public func resume() {}

    public func teardown() {
        tornDown = true
        frame = ShapePathFrame()
    }
}
