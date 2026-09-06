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
        guard !tornDown else { return EncodeReport(encodeNs: 0, pointsDrawn: 0, drawCalls: 0) }
        defer { encodedRevision += 1 }
        frame = SwiftChartsChartRenderer.encode(prepared)
        return EncodeReport(
            encodeNs: frame.encodeNs,
            pointsDrawn: frame.pointsDrawn,
            // `Chart` compiles its own draw commands for whatever renders it — Core Animation on
            // iOS — on a thread this process does not observe, so how many submissions that costs
            // is not a number this backend has. `nil` is the honest answer, not the mark count
            // standing in for a different quantity `drawCalls` is defined to be.
            drawCalls: nil
        )
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
