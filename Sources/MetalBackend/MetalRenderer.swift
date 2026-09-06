import BenchHost
import BenchRuntime
import Foundation
import Metal
import SwiftUI

/// `ChartRenderer` conformer for the Metal backend.
///
/// `init()` builds the `MTLDevice` and `MetalLineRenderer` this backend needs, once, so a host
/// with no GPU is a fact known here before the first `encode(_:)` rather than discovered later by
/// a `try?` buried inside a SwiftUI coordinator created lazily on first appearance. See the card
/// report's answer to the contract's first open question for why `init()` does not take one either.
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

    /// Multisample count shared with the `MTKView` `MetalChartView` configures: building the
    /// pipeline against one sample count and drawing into a view configured for another is a
    /// validation failure at draw time, not a difference in output.
    ///
    /// `nonisolated`: a plain `Int` constant, read from `Coordinator`, which is not itself
    /// main-actor isolated.
    nonisolated static let sampleCount = 4

    /// `nil` on a host with no Metal device. `encode(_:)` reads this, not a swallowed `try?`, to
    /// know whether anything can actually draw before it reports a count.
    let device: MTLDevice?
    /// `nil` when there is no device, or when building the pipeline failed on one that exists.
    let lineRenderer: MetalLineRenderer?
    /// Why `lineRenderer` is `nil`; `nil` itself once it built successfully. Captured here instead
    /// of swallowed by the `try?` this replaces inside `MetalChartView.Coordinator`.
    let initializationFailure: MetalRendererError?

    /// Last frame `encode(_:)` built. `surface` reads it, so a stalled renderer that stopped
    /// encoding would freeze on whatever is here rather than fail silently.
    private(set) var geometry = MetalChartGeometry()
    private var layout = ChromeLayout.empty
    public private(set) var encodedRevision: UInt64 = 0
    private let rasterTime = RasterTimeRecorder()
    private let gpuTime = RasterTimeRecorder()
    private var tornDown = false

    public convenience init() {
        self.init(device: MTLCreateSystemDefaultDevice())
    }

    /// Test seam: builds a renderer as if the host had no device (or a specific one), without
    /// needing to fake `MTLCreateSystemDefaultDevice()` itself.
    init(device: MTLDevice?) {
        guard let device else {
            self.device = nil
            self.lineRenderer = nil
            self.initializationFailure = .noDevice
            return
        }
        self.device = device
        do {
            self.lineRenderer = try MetalLineRenderer(
                device: device,
                pixelFormat: MetalRenderTarget.pixelFormat,
                sampleCount: Self.sampleCount
            )
            self.initializationFailure = nil
        } catch {
            self.lineRenderer = nil
            self.initializationFailure = error
        }
    }

    public func encode(_ prepared: PreparedFrame) -> EncodeReport {
        defer { encodedRevision += 1 }
        guard !tornDown else { return EncodeReport(encodeNs: 0, pointsDrawn: 0, drawCalls: 0) }

        let clock = ContinuousClock()
        var built = MetalChartGeometry()
        let elapsed = clock.measure { built = MetalChartGeometry.build(prepared, scale: prepared.scale) }
        geometry = built
        layout = prepared.chrome

        // No device, no line renderer: nothing drawn this frame is a fact, not a guess, and
        // reporting the geometry's own counts here would be exactly the failure this backend
        // exists to catch — a host that cannot draw at all posting the fastest row in the table.
        guard lineRenderer != nil else {
            return EncodeReport(encodeNs: elapsed.nanoseconds, pointsDrawn: nil, drawCalls: nil)
        }

        return EncodeReport(
            encodeNs: elapsed.nanoseconds,
            pointsDrawn: samplesDrawn(in: prepared),
            // One draw call per batch: the grid and axes share a batch when they share a style,
            // and every series is its own — the same count `MetalLineRenderer.draw` will later
            // issue, known here without touching the GPU because it falls out of the geometry
            // alone.
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
            device: device,
            lineRenderer: lineRenderer,
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
