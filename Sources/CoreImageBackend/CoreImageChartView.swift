#if os(iOS)
import BenchCore
import BenchRuntime
import CoreImage
import Metal
import MetalKit
import SwiftUI

/// An `MTKView` that delivers one already-rasterised, already-filtered frame through a Core Image
/// render, and nothing else.
///
/// **It does not run `MTKView`'s display link**, for the same reason `MetalChartView` does not:
/// `isPaused` and `enableSetNeedsDisplay` are both off, so the view draws only when the scene's
/// clock says to. Left at its defaults the view would bring its own timer, and the backend would
/// be measured against a different number of frames from the ones it is compared with.
public struct CoreImageChartView: View {
    private let image: CIImage?
    private let layout: ChromeLayout
    private let encodedRevision: UInt64
    private let device: MTLDevice?
    private let context: CIContext?
    private let rasterTime: RasterTimeRecorder?
    private let gpuTime: RasterTimeRecorder?

    /// - Parameters:
    ///   - encodedRevision: Which `encode()` call produced `image`. Tagged onto whatever this draw
    ///     reports, because a completion handler can fire for an older frame than the one `image`
    ///     now holds.
    ///   - device, context: Owned by `CoreImageRenderer`, not built here — a host with no device
    ///     hands both through as `nil`, and the coordinator below never tries to build its own.
    public init(
        image: CIImage?,
        layout: ChromeLayout,
        encodedRevision: UInt64 = 0,
        device: MTLDevice? = nil,
        context: CIContext? = nil,
        rasterTime: RasterTimeRecorder? = nil,
        gpuTime: RasterTimeRecorder? = nil
    ) {
        self.image = image
        self.layout = layout
        self.encodedRevision = encodedRevision
        self.device = device
        self.context = context
        self.rasterTime = rasterTime
        self.gpuTime = gpuTime
    }

    public var body: some View {
        ZStack {
            CoreImageChartSurface(
                image: image,
                background: layout.background,
                encodedRevision: encodedRevision,
                device: device,
                context: context,
                rasterTime: rasterTime,
                gpuTime: gpuTime
            )
            CoreImageChartLabels(layout: layout)
        }
    }
}

/// The drawing surface. Separated so that only this view reads the per-frame image.
struct CoreImageChartSurface: UIViewRepresentable {
    let image: CIImage?
    let background: PaletteColor
    let encodedRevision: UInt64
    let device: MTLDevice?
    let context: CIContext?
    let rasterTime: RasterTimeRecorder?
    let gpuTime: RasterTimeRecorder?

    func makeCoordinator() -> Coordinator {
        Coordinator(device: device, context: context, background: background, rasterTime: rasterTime, gpuTime: gpuTime)
    }

    func makeUIView(context viewContext: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: viewContext.coordinator.device)
        view.colorPixelFormat = .bgra8Unorm_srgb
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        // Core Image writes into the drawable's texture through its own render and compute
        // passes, which a `framebufferOnly` texture refuses: this view exists only to host that
        // write, so the restriction buys it nothing and would silently break the render.
        view.framebufferOnly = false
        view.delegate = viewContext.coordinator
        view.clearColor = MTLClearColor(
            red: background.red,
            green: background.green,
            blue: background.blue,
            alpha: 1
        )
        return view
    }

    func updateUIView(_ view: MTKView, context viewContext: Context) {
        viewContext.coordinator.image = image
        viewContext.coordinator.background = background
        viewContext.coordinator.encodedRevision = encodedRevision
        // The scene's tick, arriving as a state change. `draw()` is synchronous and this is the
        // only thing that calls it.
        view.draw()
    }

    /// Holds what must survive a view update: the device and the `CIContext` built against it.
    ///
    /// Rebuilding a `CIContext` per update would repeat whatever setup cost building one carries,
    /// inside what is supposed to be a frame — the same reason `MetalChartView.Coordinator` holds
    /// its compiled pipeline rather than rebuilding it.
    final class Coordinator: NSObject, MTKViewDelegate {
        let device: MTLDevice?
        var image: CIImage?
        var background: PaletteColor
        /// Which `encode()` call `image` came from. Read at the top of `draw(in:)` into a local,
        /// because a completion handler queued from an earlier call must keep reporting the
        /// revision it was drawn for even after this property has moved on to a newer one.
        var encodedRevision: UInt64 = 0
        private let context: CIContext?
        private let queue: MTLCommandQueue?
        private let rasterTime: RasterTimeRecorder?
        private let gpuTime: RasterTimeRecorder?

        /// Takes the device and context as built by `CoreImageRenderer`, rather than building its
        /// own: a coordinator created lazily by SwiftUI on first appearance is the wrong place to
        /// discover — and swallow — whether this host can draw at all.
        init(device: MTLDevice?, context: CIContext?, background: PaletteColor, rasterTime: RasterTimeRecorder?, gpuTime: RasterTimeRecorder?) {
            self.device = device
            self.context = context
            self.queue = device?.makeCommandQueue()
            self.background = background
            self.rasterTime = rasterTime
            self.gpuTime = gpuTime
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        func draw(in view: MTKView) {
            guard let context, let image,
                  let drawable = view.currentDrawable,
                  let commandBuffer = queue?.makeCommandBuffer() else { return }

            // Captured now, not read from the property inside the completion handler below: see
            // `MetalChartView.Coordinator.draw(in:)` for why.
            let revision = encodedRevision

            let clock = ContinuousClock()
            let elapsed = clock.measure {
                context.render(
                    image,
                    to: drawable.texture,
                    commandBuffer: commandBuffer,
                    bounds: CGRect(
                        origin: .zero,
                        size: CGSize(width: view.drawableSize.width, height: view.drawableSize.height)
                    ),
                    colorSpace: PaletteColor.sRGB
                )
            }
            rasterTime?.record(nanoseconds: elapsed.nanoseconds, encodedRevision: revision)

            // The GPU's own clock, not the host's — see `MetalChartView.Coordinator.draw(in:)`.
            if let gpuTime {
                commandBuffer.addCompletedHandler { buffer in
                    let seconds = buffer.gpuEndTime - buffer.gpuStartTime
                    guard seconds > 0 else { return }
                    gpuTime.record(nanoseconds: UInt64(seconds * 1_000_000_000), encodedRevision: revision)
                }
            }
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }
}

/// Axis labels, drawn by SwiftUI over the Core Image surface, from the same layout every other
/// backend strokes. `CoreGraphicsReference` — and so this backend's own raster — never draws text;
/// see its doc comment for why.
struct CoreImageChartLabels: View {
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
