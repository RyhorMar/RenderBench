import BenchHost
import BenchRuntime
import Foundation
import Metal
import SwiftUI

/// `ChartRenderer` conformer for the Metal compute backend.
///
/// `init()` builds the `MTLDevice`, the reduction pipeline and the line pipeline once, exactly as
/// `Sources/MetalBackend/MetalRenderer.swift` does and for the same reason: a host with no GPU is a
/// fact known here, before the first `encode(_:)`, rather than discovered later by a coordinator
/// created lazily on first appearance.
@MainActor
@Observable
public final class MetalComputeRenderer: ChartRenderer {
    /// The only descriptor in the catalogue with `reducesOnGPU: true` — see its doc comment on
    /// `RendererDescriptor` for what that changes upstream, in `Demo/Sources/ChartScene.swift`.
    public static let descriptor = RendererDescriptor(
        identifier: MetalComputeBackend.identifier,
        displayName: "Metal compute",
        reportsRasterTime: true,
        reportsGPUTime: true,
        reducesOnGPU: true
    )
    public static var capabilities: [Capability] { MetalComputeBackend.capabilities }

    /// Shared with the `MTKView` `MetalComputeChartView` configures — see `MetalRenderer`'s own
    /// `sampleCount` for why the two must agree.
    nonisolated static let sampleCount = 4

    let device: MTLDevice?
    let reducer: MetalComputeReducer?
    let lineRenderer: MetalComputeLineRenderer?
    let initializationFailure: MetalComputeError?

    private(set) var geometry = MetalComputeChartGeometry()
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
            self.reducer = nil
            self.lineRenderer = nil
            self.initializationFailure = .noDevice
            return
        }
        self.device = device
        do {
            let reducer = try MetalComputeReducer(device: device)
            let lineRenderer = try MetalComputeLineRenderer(
                device: device,
                pixelFormat: MetalComputeRenderTarget.pixelFormat,
                sampleCount: Self.sampleCount
            )
            self.reducer = reducer
            self.lineRenderer = lineRenderer
            self.initializationFailure = nil
        } catch {
            self.reducer = nil
            self.lineRenderer = nil
            self.initializationFailure = error
        }
    }

    public func encode(_ prepared: PreparedFrame) -> EncodeReport {
        // Known zeros, not unknowable `nil`s: this backend counts its own submissions, so once
        // torn down it genuinely submitted none — the same reasoning `MetalRenderer` reports for
        // itself, and the opposite of the render-server backends, which never know a submission
        // count at all and must report `nil` in both states.
        guard !tornDown else { return EncodeReport(encodeNs: 0, pointsDrawn: 0, drawCalls: 0) }
        defer { encodedRevision += 1 }

        guard let reducer else {
            // No device at all: nothing drawn this frame is a fact, not a guess, and it is the
            // same fact `MetalRenderer` reports the same way for the same reason — a host that
            // cannot draw must not post the fastest row in the table.
            return EncodeReport(encodeNs: 0, pointsDrawn: nil, drawCalls: nil)
        }

        let clock = ContinuousClock()
        var built = MetalComputeChartGeometry()
        var pointsDrawn = 0
        var reductionFailed = false

        let elapsed = clock.measure {
            guard prepared.plotRect.isDrawable else { return }
            let runsPerSeries = prepared.series.map { RunSplitter.runs(in: $0.points) }
            do {
                // The synchronous readback lives inside `reduce(runsPerSeries:plotWidth:)` and its
                // cost is inside this `measure` block on purpose: it is the one price this design
                // pays that no other backend pays in the same place, and hiding it outside the
                // timed section would report a frame time this backend never actually achieved.
                let reduced = try reducer.reduce(runsPerSeries: runsPerSeries, plotWidth: prepared.plotRect.width)
                for series in reduced {
                    for run in series { pointsDrawn += run.points.count }
                }
                built = MetalComputeChartGeometry.build(prepared, reducedRuns: reduced, scale: prepared.scale)
            } catch {
                reductionFailed = true
            }
        }
        geometry = built
        layout = prepared.chrome

        guard lineRenderer != nil, !reductionFailed else {
            return EncodeReport(encodeNs: elapsed.nanoseconds, pointsDrawn: nil, drawCalls: nil)
        }

        return EncodeReport(
            encodeNs: elapsed.nanoseconds,
            pointsDrawn: pointsDrawn,
            // One draw call per batch, known here without touching the GPU render pass itself,
            // the same way `MetalRenderer` counts its own: it falls out of the geometry alone,
            // and is the same count `MetalComputeLineRenderer.draw` will issue.
            drawCalls: built.batches.count
        )
    }

    public func takeDeferredTimes() -> DeferredTimes {
        DeferredTimes(raster: rasterTime.take(), gpu: gpuTime.take(), presentedTime: nil)
    }

    public var surface: AnyView {
        #if os(iOS)
        AnyView(MetalComputeChartView(
            geometry: geometry,
            layout: layout,
            encodedRevision: encodedRevision,
            device: device,
            lineRenderer: lineRenderer,
            rasterTime: rasterTime,
            gpuTime: gpuTime
        ))
        #else
        // `MetalComputeChartView` is `#if os(iOS)` for the same reason `MetalChartView` is:
        // `MTKView` and `UIViewRepresentable` do not exist on macOS, where `swift test` runs.
        AnyView(EmptyView())
        #endif
    }

    // No display link of its own, for the same reason `MetalRenderer` has none: `MTKView` here
    // never runs its own timer, so there is no ongoing GPU cost to suspend between ticks.
    public func suspend() {}
    public func resume() {}

    public func teardown() {
        tornDown = true
        self.geometry = MetalComputeChartGeometry()
    }
}
