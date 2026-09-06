import BenchHost
import BenchRuntime
import SwiftUI

/// `ChartRenderer` conformer for the Shader backend.
///
/// Nothing here owns a device, a display link, or a command buffer: `chart_line` runs inside
/// SwiftUI's own compositor, on its own thread, after `encode(_:)` has already returned — the same
/// shape of problem `ShapePathRenderer` and `CoreAnimationRenderer` both have, and the same answer
/// follows from it below.
@MainActor
@Observable
public final class ShaderRenderer: ChartRenderer {
    /// Identity and reporting capabilities: SwiftUI's compositor rasterises this backend's
    /// `colorEffect` values on its own thread, after `encode(_:)` has already returned, and does so
    /// inside the system's own render pass — not one this process can attach a timer or a GPU
    /// counter to — so neither raster nor GPU time is ever observable here.
    public static let descriptor = RendererDescriptor(
        identifier: ShaderBackend.identifier,
        displayName: "SwiftUI Shader",
        reportsRasterTime: false,
        reportsGPUTime: false
    )
    public static var capabilities: [Capability] { ShaderBackend.capabilities }

    /// Last frame `encode(_:)` built. `surface` reads it, so a stalled renderer that stopped
    /// encoding would freeze on whatever is here rather than fail silently.
    private(set) var frame = ShaderFrame()
    public private(set) var encodedRevision: UInt64 = 0
    private var tornDown = false

    public init() {}

    public func encode(_ prepared: PreparedFrame) -> EncodeReport {
        // `drawCalls` is `nil` whether torn down or active: a `colorEffect` handed to `Rectangle`
        // becomes whatever draw commands SwiftUI's compositor submits, on a thread this process
        // does not observe — the same reason `ShapePathRenderer.encode(_:)` never reports one
        // either. `pointsDrawn` differs: it is this backend's own submission count, so `0` once
        // torn down is a true report of nothing submitted, not a guess standing in for "unknown".
        guard !tornDown else { return EncodeReport(encodeNs: 0, pointsDrawn: 0, drawCalls: nil) }
        defer { encodedRevision += 1 }
        frame = ShaderChartRenderer.encode(prepared)
        return EncodeReport(encodeNs: frame.encodeNs, pointsDrawn: frame.pointsDrawn, drawCalls: nil)
    }

    public func takeDeferredTimes() -> DeferredTimes { .none }

    public var surface: AnyView {
        AnyView(ShaderChartView(frame: frame))
    }

    // Every run sits inert between ticks with nothing of its own consuming compositor work
    // between frames, so there is nothing here to pause.
    public func suspend() {}
    public func resume() {}

    public func teardown() {
        tornDown = true
        frame = ShaderFrame()
    }
}
