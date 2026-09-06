import BenchHost
import BenchRuntime
import Foundation
import SwiftUI

/// `ChartRenderer` conformer for the Metal backend.
///
/// `encode(_:)` only builds geometry — no `MTLDevice` touched, nothing that can throw. The device,
/// the pipeline and `MetalLineRenderer` itself live inside ``MetalChartView``'s coordinator,
/// created lazily by SwiftUI and already tolerant of a host with no GPU. See the card report's
/// answer to the contract's first open question for why `init()` does not take one either.
@MainActor
@Observable
public final class MetalRenderer: ChartRenderer {
    /// Identity and reporting capabilities: the only backend so far whose rasterisation is
    /// GPU-timed rather than inferred.
    public static let descriptor = RendererDescriptor(
        identifier: MetalBackend.identifier,
        displayName: "Metal",
        reportsRasterTime: true,
        reportsGPUTime: true
    )
    public static var capabilities: [Capability] { MetalBackend.capabilities }

    /// Last frame `encode(_:)` built. `surface` reads it, so a stalled renderer that stopped
    /// encoding would freeze on whatever is here rather than fail silently.
    private(set) var geometry = MetalChartGeometry()
    private var layout = ChromeLayout.empty
    public private(set) var encodedRevision: UInt64 = 0
    private let rasterTime = RasterTimeRecorder()
    private let gpuTime = RasterTimeRecorder()
    private var tornDown = false

    public init() {}

    public func encode(_ prepared: PreparedFrame) -> EncodeReport {
        defer { encodedRevision += 1 }
        guard !tornDown else { return EncodeReport(encodeNs: 0, pointsDrawn: 0, drawCalls: 0) }

        let clock = ContinuousClock()
        var built = MetalChartGeometry()
        let elapsed = clock.measure { built = MetalChartGeometry.build(prepared, scale: prepared.scale) }
        geometry = built
        layout = prepared.chrome

        return EncodeReport(
            encodeNs: elapsed.nanoseconds,
            pointsDrawn: samplesDrawn(in: prepared),
            // One draw call per batch: the grid and axes share a batch when they share a style,
            // and every series is its own — the same count `MetalLineRenderer.draw` will later
            // issue, known here without a device because it falls out of the geometry alone.
            drawCalls: built.batches.count
        )
    }

    /// Samples actually turned into geometry, excluding chrome and breaks.
    ///
    /// Not read off `geometry.points.count`: that buffer mixes chrome vertices in with the
    /// series', and a run of exactly one point between two breaks contributes a vertex there but
    /// no segment, so neither number answers "how many samples did this frame draw."
    private func samplesDrawn(in prepared: PreparedFrame) -> Int {
        guard prepared.plotRect.isDrawable else { return 0 }
        var drawn = 0
        for series in prepared.series {
            for point in series.points where !point.isBreak { drawn += 1 }
        }
        return drawn
    }

    public func takeDeferredTimes() -> DeferredTimes {
        DeferredTimes(raster: rasterTime.take(), gpu: gpuTime.take(), presentedTime: nil)
    }

    public var surface: AnyView {
        #if os(iOS)
        AnyView(MetalChartView(
            geometry: geometry,
            layout: layout,
            encodedRevision: encodedRevision,
            rasterTime: rasterTime,
            gpuTime: gpuTime
        ))
        #else
        // `MetalChartView` is `#if os(iOS)` for the same reason it is here: `MTKView` and
        // `UIViewRepresentable` do not exist on macOS, and `swift test` runs there. The real
        // surface is exercised by `xcodebuild ... -destination 'generic/platform=iOS Simulator'
        // build`.
        AnyView(EmptyView())
        #endif
    }

    // No display link of its own: `MTKView` here never runs its own timer, so there is no
    // ongoing GPU cost to suspend between ticks.
    public func suspend() {}
    public func resume() {}

    public func teardown() {
        tornDown = true
        self.geometry = MetalChartGeometry()
    }
}
