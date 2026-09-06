import BenchHost
import BenchRuntime
import SwiftUI

/// `ChartRenderer` conformer for the `Canvas` backend.
///
/// Everything it needs to draw arrives through `encode(_:)` on `PreparedFrame`: no host context,
/// no device. `init()` carries nothing because this method never touches one — see the card
/// report's answer to the contract's first open question for why the other two backends agree.
@MainActor
@Observable
public final class CanvasRenderer: ChartRenderer {
    /// Identity and reporting capabilities: this backend times its own draw pass and never reads
    /// GPU timestamps.
    public static let descriptor = RendererDescriptor(
        identifier: CanvasBackend.identifier,
        displayName: "Canvas",
        reportsRasterTime: true,
        reportsGPUTime: false
    )
    public static var capabilities: [Capability] { CanvasBackend.capabilities }

    /// Last frame `encode(_:)` built. `surface` reads it, so a stalled renderer that stopped
    /// encoding would freeze on whatever is here rather than fail silently.
    private(set) var frame = CanvasFrame()
    public private(set) var encodedRevision: UInt64 = 0
    private let rasterTime = RasterTimeRecorder()
    private var tornDown = false

    public init() {}

    public func encode(_ prepared: PreparedFrame) -> EncodeReport {
        defer { encodedRevision += 1 }
        guard !tornDown else { return EncodeReport(encodeNs: 0, pointsDrawn: 0, drawCalls: 0) }
        frame = CanvasChartRenderer.encode(prepared)
        return EncodeReport(encodeNs: frame.encodeNs, pointsDrawn: frame.pointsDrawn, drawCalls: frame.strokes.count)
    }

    public func takeDeferredTimes() -> DeferredTimes {
        DeferredTimes(raster: rasterTime.take(), gpu: nil, presentedTime: nil)
    }

    public var surface: AnyView {
        AnyView(CanvasChartView(frame: frame, recorder: rasterTime, encodedRevision: encodedRevision))
    }

    // No display link of its own and nothing to pause: a `Canvas` only draws when the scene's
    // tick changes its input, so there is no ongoing cost to suspend in the first place.
    public func suspend() {}
    public func resume() {}

    public func teardown() {
        tornDown = true
        frame = CanvasFrame()
    }
}
