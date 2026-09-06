#if os(iOS)
import BenchCore
import BenchRuntime
import Metal
import MetalKit
import SwiftUI
import simd

/// An `MTKView` that draws one prepared frame, and nothing else.
///
/// **It does not run `MTKView`'s display link.** `isPaused` and `enableSetNeedsDisplay` are both
/// off, so the view draws only when the scene's clock says to. Left at its defaults the view would
/// bring its own timer, and the backend would be measured against a different number of frames
/// from the ones it is compared with — one tick per scene is an invariant of this project, not a
/// preference.
///
/// Labels are not drawn here. Metal has no text, and a chart that needs axis labels either builds
/// a glyph atlas or lets something else draw them; this composes a SwiftUI overlay, which is what
/// the method actually costs in practice. The overlay is a separate view so that the per-frame
/// body stays confined to the surface.
public struct MetalChartView: View {
    private let geometry: MetalChartGeometry
    private let layout: ChromeLayout
    private let encodedRevision: UInt64
    private let device: MTLDevice?
    private let lineRenderer: MetalLineRenderer?
    private let rasterTime: RasterTimeRecorder?
    private let gpuTime: RasterTimeRecorder?

    /// - Parameters:
    ///   - encodedRevision: Which `encode()` call produced `geometry`. Tagged onto whatever this
    ///     draw reports, because with several frames in flight a completion handler can fire for
    ///     an older frame than the one `geometry` now holds.
    ///   - device, lineRenderer: Owned by `MetalRenderer`, not built here — a host with no device
    ///     hands both through as `nil`, and the coordinator below never tries to create its own.
    public init(
        geometry: MetalChartGeometry,
        layout: ChromeLayout,
        encodedRevision: UInt64 = 0,
        device: MTLDevice? = nil,
        lineRenderer: MetalLineRenderer? = nil,
        rasterTime: RasterTimeRecorder? = nil,
        gpuTime: RasterTimeRecorder? = nil
    ) {
        self.geometry = geometry
        self.layout = layout
        self.encodedRevision = encodedRevision
        self.device = device
        self.lineRenderer = lineRenderer
        self.rasterTime = rasterTime
        self.gpuTime = gpuTime
    }

    public var body: some View {
        ZStack {
            MetalChartSurface(
                geometry: geometry,
                background: layout.background,
                encodedRevision: encodedRevision,
                device: device,
                lineRenderer: lineRenderer,
                rasterTime: rasterTime,
                gpuTime: gpuTime
            )
            MetalChartLabels(layout: layout)
        }
    }
}

/// The drawing surface. Separated so that only this view reads the per-frame geometry.
struct MetalChartSurface: UIViewRepresentable {
    let geometry: MetalChartGeometry
    let background: PaletteColor
    let encodedRevision: UInt64
    let device: MTLDevice?
    let lineRenderer: MetalLineRenderer?
    let rasterTime: RasterTimeRecorder?
    let gpuTime: RasterTimeRecorder?

    func makeCoordinator() -> Coordinator {
        Coordinator(device: device, renderer: lineRenderer, background: background, rasterTime: rasterTime, gpuTime: gpuTime)
    }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: context.coordinator.device)
        view.colorPixelFormat = MetalRenderTarget.pixelFormat
        view.sampleCount = Coordinator.sampleCount
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        // Nothing reads the drawable back, so the driver may keep it in whatever layout is
        // fastest to render into.
        view.framebufferOnly = true
        view.delegate = context.coordinator
        // A clear colour is set per pass by the renderer; this only covers the moment before the
        // first frame exists.
        view.clearColor = MTLClearColor(
            red: background.red,
            green: background.green,
            blue: background.blue,
            alpha: 1
        )
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        context.coordinator.geometry = geometry
        context.coordinator.background = background
        context.coordinator.encodedRevision = encodedRevision
        // The scene's tick, arriving as a state change. `draw()` is synchronous and this is the
        // only thing that calls it.
        view.draw()
    }

    /// Holds what must survive a view update: the device, the renderer and its compiled shader.
    ///
    /// Rebuilding these per update would recompile the shader — 48 ms on an M3 Pro — inside what
    /// is supposed to be a frame.
    final class Coordinator: NSObject, MTKViewDelegate {
        /// Mirrors `MetalRenderer.sampleCount` rather than a literal of its own: the view's
        /// `MTKView.sampleCount` and the pipeline `MetalRenderer` built `renderer` against must
        /// match, or a draw fails validation.
        static let sampleCount = MetalRenderer.sampleCount

        let device: MTLDevice?
        var geometry = MetalChartGeometry()
        var background: PaletteColor
        /// Which `encode()` call `geometry` came from. Read at the top of `draw(in:)` into a
        /// local, because a completion handler queued from an earlier call must keep reporting
        /// the revision it was drawn for even after this property has moved on to a newer one.
        var encodedRevision: UInt64 = 0
        /// Set when an attempted draw failed inside `draw(in:)` itself — for example no encoder
        /// available on a frame that otherwise had a device and a renderer. Not set when there is
        /// no device or renderer at all: that fact is captured once, in `MetalRenderer.init()`,
        /// and is already why `encode(_:)` reported `nil` counters for this frame rather than
        /// leaving a blank chart unexplained.
        private(set) var lastFailure: MetalRendererError?
        private let renderer: MetalLineRenderer?
        private let queue: MTLCommandQueue?
        private let rasterTime: RasterTimeRecorder?
        private let gpuTime: RasterTimeRecorder?

        /// Takes the device and renderer as built by `MetalRenderer`, rather than building its
        /// own: a coordinator created lazily by SwiftUI on first appearance is the wrong place to
        /// discover — and swallow — whether this host can draw at all.
        init(device: MTLDevice?, renderer: MetalLineRenderer?, background: PaletteColor, rasterTime: RasterTimeRecorder?, gpuTime: RasterTimeRecorder?) {
            self.device = device
            self.renderer = renderer
            self.queue = device?.makeCommandQueue()
            self.background = background
            self.rasterTime = rasterTime
            self.gpuTime = gpuTime
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        func draw(in view: MTKView) {
            guard let renderer, let queue,
                  let descriptor = view.currentRenderPassDescriptor,
                  let drawable = view.currentDrawable,
                  let commandBuffer = queue.makeCommandBuffer() else { return }

            // Captured now, not read from the property inside the completion handler below: with
            // several frames in flight, `encodedRevision` can have moved to a newer frame by the
            // time that handler runs, and the reading must stay tagged with the frame it drew.
            let revision = encodedRevision

            // Timed with an explicit pair of readings rather than `measure`: the closure form
            // erases the typed throw to `any Error`, and the point of typing it was to know that
            // a draw failure is the only thing that can arrive here.
            var encoded = false
            let clock = ContinuousClock()
            let started = clock.now
            do {
                try renderer.draw(
                    geometry,
                    viewportPixels: SIMD2<Float>(
                        Float(view.drawableSize.width),
                        Float(view.drawableSize.height)
                    ),
                    clearColour: background,
                    descriptor: descriptor,
                    in: commandBuffer
                )
                encoded = true
            } catch {
                lastFailure = error
            }
            let elapsed = clock.now - started
            // A frame that failed to encode reports no time rather than a small one. The
            // alternative is a backend that gets faster the more often it fails to draw.
            if encoded { rasterTime?.record(nanoseconds: elapsed.nanoseconds, encodedRevision: revision) }

            // The GPU's own clock, not the host's. It arrives after the frame that produced it and
            // is collected on a later tick — the one column in this project that measures
            // rasterisation directly rather than by subtraction.
            if encoded, let gpuTime {
                commandBuffer.addCompletedHandler { buffer in
                    let seconds = buffer.gpuEndTime - buffer.gpuStartTime
                    guard seconds > 0 else { return }
                    gpuTime.record(nanoseconds: UInt64(seconds * 1_000_000_000), encodedRevision: revision)
                }
            }
            if encoded { commandBuffer.present(drawable) }
            commandBuffer.commit()
        }
    }
}

/// Axis labels, drawn by SwiftUI over the Metal surface, from the same layout every other backend
/// strokes — this view places no tick itself.
struct MetalChartLabels: View {
    let layout: ChromeLayout

    private static let labelFont = Font.system(size: 9, design: .monospaced)

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { context, _ in
            for entry in layout.labels {
                let anchor: UnitPoint = entry.anchor == .trailing ? .trailing : .center
                context.draw(context.resolve(label(entry.text)), at: CGPoint(x: entry.x, y: entry.y), anchor: anchor)
            }
        }
        .allowsHitTesting(false)
    }

    private func label(_ text: String) -> Text {
        Text(text)
            .font(Self.labelFont)
            .foregroundStyle(
                Color(.sRGBLinear, red: layout.labelColour.red, green: layout.labelColour.green, blue: layout.labelColour.blue)
            )
    }
}
#endif
