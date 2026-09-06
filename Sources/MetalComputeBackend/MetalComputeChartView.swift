#if os(iOS)
import BenchCore
import BenchRuntime
import Metal
import MetalKit
import SwiftUI

/// An `MTKView` that draws one already-reduced frame, and nothing else.
///
/// Duplicated in shape from `Sources/MetalBackend/MetalChartView.swift`'s `MetalChartView`, for
/// the reason given on `MetalComputeLineGeometry`. It does not run `MTKView`'s own display link,
/// for the same reason that one does not: one tick per scene is an invariant of this project, not
/// a preference, and this view draws only when `updateUIView` says to.
public struct MetalComputeChartView: View {
    private let geometry: MetalComputeChartGeometry
    private let layout: ChromeLayout
    private let encodedRevision: UInt64
    private let device: MTLDevice?
    private let lineRenderer: MetalComputeLineRenderer?
    private let rasterTime: RasterTimeRecorder?
    private let gpuTime: RasterTimeRecorder?

    init(
        geometry: MetalComputeChartGeometry,
        layout: ChromeLayout,
        encodedRevision: UInt64 = 0,
        device: MTLDevice? = nil,
        lineRenderer: MetalComputeLineRenderer? = nil,
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
            MetalComputeChartSurface(
                geometry: geometry,
                background: layout.background,
                encodedRevision: encodedRevision,
                device: device,
                lineRenderer: lineRenderer,
                rasterTime: rasterTime,
                gpuTime: gpuTime
            )
            MetalComputeChartLabels(layout: layout)
        }
    }
}

/// The drawing surface. Separated so that only this view reads the per-frame geometry.
struct MetalComputeChartSurface: UIViewRepresentable {
    let geometry: MetalComputeChartGeometry
    let background: PaletteColor
    let encodedRevision: UInt64
    let device: MTLDevice?
    let lineRenderer: MetalComputeLineRenderer?
    let rasterTime: RasterTimeRecorder?
    let gpuTime: RasterTimeRecorder?

    func makeCoordinator() -> Coordinator {
        Coordinator(device: device, renderer: lineRenderer, background: background, rasterTime: rasterTime, gpuTime: gpuTime)
    }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: context.coordinator.device)
        view.colorPixelFormat = MetalComputeRenderTarget.pixelFormat
        view.sampleCount = Coordinator.sampleCount
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        view.framebufferOnly = true
        view.delegate = context.coordinator
        view.clearColor = MTLClearColor(
            red: background.red, green: background.green, blue: background.blue, alpha: 1
        )
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        context.coordinator.geometry = geometry
        context.coordinator.background = background
        context.coordinator.encodedRevision = encodedRevision
        view.draw()
    }

    /// Holds what must survive a view update: the device and the renderer, built once by
    /// `MetalComputeRenderer` — never here. A coordinator that built its own device lazily is
    /// exactly the defect a prior card introduced and later had to remove: `encode(_:)` can never
    /// see a failure that a lazily-created device inside a view coordinator swallows.
    final class Coordinator: NSObject, MTKViewDelegate {
        static let sampleCount = MetalComputeRenderer.sampleCount

        let device: MTLDevice?
        var geometry = MetalComputeChartGeometry()
        var background: PaletteColor
        var encodedRevision: UInt64 = 0
        private(set) var lastFailure: MetalComputeError?
        private let renderer: MetalComputeLineRenderer?
        private let queue: MTLCommandQueue?
        private let rasterTime: RasterTimeRecorder?
        private let gpuTime: RasterTimeRecorder?

        init(device: MTLDevice?, renderer: MetalComputeLineRenderer?, background: PaletteColor, rasterTime: RasterTimeRecorder?, gpuTime: RasterTimeRecorder?) {
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

            let revision = encodedRevision

            var encoded = false
            let clock = ContinuousClock()
            let started = clock.now
            do {
                try renderer.draw(
                    geometry,
                    viewportPixels: SIMD2<Float>(
                        Float(view.drawableSize.width), Float(view.drawableSize.height)
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
            if encoded { rasterTime?.record(nanoseconds: elapsed.nanoseconds, encodedRevision: revision) }

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

/// Axis labels, drawn by SwiftUI over the Metal surface — same treatment as `MetalChartLabels`.
struct MetalComputeChartLabels: View {
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
