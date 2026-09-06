import BenchHost
import BenchRuntime
import SwiftUI

/// `ChartRenderer` conformer for the Swift Charts backend.
///
/// Nothing here owns a device or a display link: `Chart` renders through SwiftUI's own render
/// server, on its own thread, after `encode(_:)` has already returned — the same shape of problem
/// `CoreAnimationRenderer` has, and the same answer follows from it below.
@MainActor
@Observable
public final class SwiftChartsRenderer: ChartRenderer {
    /// Identity and reporting capabilities: the render server rasterises this backend's `Chart`
    /// on its own thread, after `encode(_:)` has already returned, so neither raster nor GPU
    /// time is ever observable here.
    public static let descriptor = RendererDescriptor(
        identifier: SwiftChartsBackend.identifier,
        displayName: "Swift Charts",
        reportsRasterTime: false,
        reportsGPUTime: false
    )
    public static var capabilities: [Capability] { SwiftChartsBackend.capabilities }

    /// Last frame `encode(_:)` built. `surface` reads it, so a stalled renderer that stopped
    /// encoding would freeze on whatever is here rather than fail silently.
    private(set) var frame = SwiftChartsFrame()
    public private(set) var encodedRevision: UInt64 = 0
    private var tornDown = false

    public init() {}

    public func encode(_ prepared: PreparedFrame) -> EncodeReport {
        // `drawCalls` is `nil` whether torn down or active: `Chart` compiles its own draw commands
        // for whatever renders it — Core Animation on iOS — on a thread this process does not
        // observe, so that count is never something this backend has — not the mark count standing
        // in for it, and not a torn-down `0` claiming knowledge as absent as when active.
        // `pointsDrawn` differs: it is this backend's own submission count, so `0` once torn down
        // is a true report of nothing submitted, not a guess.
        guard !tornDown else { return EncodeReport(encodeNs: 0, pointsDrawn: 0, drawCalls: nil) }
        defer { encodedRevision += 1 }
        frame = SwiftChartsChartRenderer.encode(prepared)
        return EncodeReport(encodeNs: frame.encodeNs, pointsDrawn: frame.pointsDrawn, drawCalls: nil)
    }

    public func takeDeferredTimes() -> DeferredTimes { .none }

    public var surface: AnyView {
        AnyView(SwiftChartsChartView(frame: frame))
    }

    // `Chart` sits inert between ticks with nothing of its own consuming compositor work between
    // frames, so there is nothing here to pause.
    public func suspend() {}
    public func resume() {}

    public func teardown() {
        tornDown = true
        frame = SwiftChartsFrame()
    }
}
