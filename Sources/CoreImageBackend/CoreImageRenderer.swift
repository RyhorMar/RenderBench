import BenchCore
import BenchHost
import BenchRuntime
import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import Metal
import SwiftUI

/// `ChartRenderer` conformer for the Core Image backend.
///
/// The line is never drawn by Core Image. `encode(_:)` rasterises the frame with
/// `CoreGraphicsReference.renderCGImage(_:scale:)` — the same CPU rasteriser every
/// Core-Graphics-based backend in this project is compared against — and only then hands the
/// result to a `CIColorControls` filter running on the GPU. What this backend measures is the cost
/// of delivering an already-drawn raster through a Core Image pipeline, not a cheaper way to draw
/// a line.
///
/// - SeeAlso: Docs/methods/core-image.md
///
/// Owns its `MTLDevice` and `CIContext` in `init()`, following `MetalRenderer`'s pattern in
/// `MetalBackend` exactly: a device built lazily inside a `UIViewRepresentable`'s coordinator
/// swallows a failure `encode(_:)` can never see, so a host with no GPU must be a fact known here,
/// before the first frame, rather than discovered later inside a view.
@MainActor
@Observable
public final class CoreImageRenderer: ChartRenderer {
    /// Identity and reporting capabilities: rasterisation is timed on the CPU inside `encode(_:)`,
    /// and delivery is timed on the GPU the same way `MetalRenderer` times its draw pass.
    public static let descriptor = RendererDescriptor(
        identifier: CoreImageBackend.identifier,
        displayName: "Core Image",
        reportsRasterTime: true,
        reportsGPUTime: true
    )
    public static var capabilities: [Capability] { CoreImageBackend.capabilities }

    /// The neutral value for ``saturation``: no colour shift, so a render at this value reproduces
    /// `CoreGraphicsReference`'s own bytes. Every equivalence test in this backend renders here.
    public static let neutralSaturation = 1.0

    /// Passed to `CIColorControls` each frame. Brightness and contrast stay pinned neutral —
    /// nothing in this project varies them — so this is the one knob a caller could turn to make
    /// the filter visibly do something on screen. Wiring that into the demo catalogue is out of
    /// scope for this backend.
    public var saturation: Double

    /// `nil` on a host with no Metal device. `encode(_:)` reads this, not a swallowed `try?`, to
    /// know whether anything can actually be delivered before it reports a count.
    let device: MTLDevice?
    /// `nil` when there is no device.
    let context: CIContext?
    /// Why `context` is `nil`; `nil` itself once it built successfully.
    let initializationFailure: CoreImageRendererError?

    /// Last frame `encode(_:)` rasterised and filtered. `surface` reads it, so a stalled renderer
    /// that stopped encoding would freeze on whatever is here rather than fail silently.
    private(set) var image: CIImage?
    private var layout = ChromeLayout.empty
    public private(set) var encodedRevision: UInt64 = 0
    private let rasterTime = RasterTimeRecorder()
    private let gpuTime = RasterTimeRecorder()
    private var tornDown = false

    public convenience init() {
        self.init(device: MTLCreateSystemDefaultDevice())
    }

    /// Test seam: builds a renderer as if the host had no device, without needing to fake
    /// `MTLCreateSystemDefaultDevice()` itself.
    init(device: MTLDevice?, saturation: Double = CoreImageRenderer.neutralSaturation) {
        self.saturation = saturation
        guard let device else {
            self.device = nil
            self.context = nil
            self.initializationFailure = .noDevice
            return
        }
        self.device = device
        self.context = CIContext(mtlDevice: device, options: [.workingColorSpace: PaletteColor.sRGB])
        self.initializationFailure = nil
    }

    public func encode(_ prepared: PreparedFrame) -> EncodeReport {
        guard !tornDown else { return EncodeReport(encodeNs: 0, pointsDrawn: nil, drawCalls: nil) }
        defer { encodedRevision += 1 }

        // `CoreGraphicsReference` defaults to `ComparisonImage`'s pinned canvas, sized for the
        // offscreen equivalence check. A live frame's `plotRect` is sized to the real, on-screen
        // chart instead — reconstructed here from the plot rect plus the shared insets, the same
        // arithmetic `FramePreparation.prepare` ran in reverse when it built `plotRect` from a
        // caller's `size`. Rendering at the pinned size regardless drew a correctly shaped chart
        // confined to a small corner of a 1024×768 canvas built for a different comparison, while
        // `CoreImageChartSurface` asked Core Image to fill the real, much smaller drawable from
        // that same image — the mismatch this backend's live path shipped with, caught only once a
        // test built a `PreparedFrame` at a realistic on-screen size instead of the pinned one.
        let canvasWidth = Int((prepared.plotRect.maxX + FramePreparation.rightInset).rounded())
        let canvasHeight = Int((prepared.plotRect.maxY + FramePreparation.bottomInset).rounded())

        let clock = ContinuousClock()
        var built: CIImage?
        let elapsed = clock.measure {
            guard let cgImage = CoreGraphicsReference.renderCGImage(
                prepared, scale: prepared.scale, canvasWidth: canvasWidth, canvasHeight: canvasHeight
            ) else { return }
            let filter = CIFilter.colorControls()
            filter.inputImage = CIImage(cgImage: cgImage)
            filter.saturation = Float(saturation)
            filter.brightness = 0
            filter.contrast = 1
            built = filter.outputImage
        }
        image = built
        layout = prepared.chrome

        // No device to deliver through, or the CPU raster itself produced nothing this frame:
        // either way nothing can be submitted, and reporting a count here would be exactly the
        // failure this backend exists to catch — a host that cannot draw at all posting a
        // plausible row in the table.
        guard context != nil, image != nil else {
            return EncodeReport(encodeNs: elapsed.nanoseconds, pointsDrawn: nil, drawCalls: nil)
        }
        // Samples drawn has no meaning here — the raster comes from `CoreGraphicsReference`
        // wholesale, with no per-point count crossing back into this backend. Draw calls does:
        // exactly one Core Image render is submitted per frame, to one fixed destination, unlike a
        // render server deciding its own submissions on a thread this process cannot observe.
        return EncodeReport(encodeNs: elapsed.nanoseconds, pointsDrawn: nil, drawCalls: 1)
    }

    public func takeDeferredTimes() -> DeferredTimes {
        DeferredTimes(raster: rasterTime.take(), gpu: gpuTime.take(), presentedTime: nil)
    }

    public var surface: AnyView {
        #if os(iOS)
        AnyView(CoreImageChartView(
            image: image,
            layout: layout,
            encodedRevision: encodedRevision,
            device: device,
            context: context,
            rasterTime: rasterTime,
            gpuTime: gpuTime
        ))
        #else
        // `CoreImageChartView` is `#if os(iOS)` for the same reason it is here: `MTKView` and
        // `UIViewRepresentable` do not exist on macOS, and `swift test` runs there. The real
        // surface is exercised by `xcodebuild ... -destination 'generic/platform=iOS Simulator'
        // build`.
        AnyView(EmptyView())
        #endif
    }

    // No display link of its own: the `MTKView` here never runs its own timer, so there is no
    // ongoing GPU cost to suspend between ticks.
    public func suspend() {}
    public func resume() {}

    public func teardown() {
        tornDown = true
        image = nil
    }
}
