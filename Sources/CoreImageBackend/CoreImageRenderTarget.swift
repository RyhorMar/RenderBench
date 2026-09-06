import BenchCore
import BenchRuntime
import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import Metal

/// Renders a prepared frame through the same Core Image pipeline ``CoreImageRenderer`` uses on
/// screen, off screen, at the pinned comparison format.
///
/// Built on a real `MTLDevice` rather than Core Image's software renderer, for the same reason
/// ``MetalRenderTarget`` is in `MetalBackend`: a target that rendered its comparison image on the
/// CPU while the live backend renders on the GPU would be testing a different pipeline from the
/// one being measured.
public final class CoreImageRenderTarget {
    /// Width in points. Pixels are this times the scale.
    public static let width = ComparisonImage.width
    /// Height in points.
    public static let height = ComparisonImage.height

    private let context: CIContext

    /// - Returns: `nil` when the host has no Metal device, which is a fact about the host and not
    ///   a failure of the backend — a caller in a test suite should skip, not fail.
    public init?() {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        context = CIContext(mtlDevice: device, options: [.workingColorSpace: PaletteColor.sRGB])
    }

    /// Draws a frame through the neutral Core Image pipeline and returns raw premultiplied BGRA
    /// bytes, `width * height * 4 * scale²` — the same layout `CoreGraphicsReference.render(_:scale:)`
    /// returns for the same frame.
    ///
    /// - Parameter saturation: Passed straight to `CIColorControls`. `CoreImageRenderer
    ///   .neutralSaturation` (`1`) is the value every equivalence test in this backend renders at;
    ///   brightness and contrast are pinned neutral unconditionally, since nothing in this project
    ///   varies them.
    public func render(
        _ frame: PreparedFrame,
        scale: Double = 1,
        saturation: Double = CoreImageRenderer.neutralSaturation
    ) throws(CoreImageRendererError) -> [UInt8] {
        guard let cgImage = CoreGraphicsReference.renderCGImage(frame, scale: scale) else {
            throw .noReference
        }
        let filter = CIFilter.colorControls()
        filter.inputImage = CIImage(cgImage: cgImage)
        filter.saturation = Float(saturation)
        filter.brightness = 0
        filter.contrast = 1
        guard let output = filter.outputImage else { throw .filterUnavailable }

        let pixelWidth = Int((Double(Self.width) * scale).rounded())
        let pixelHeight = Int((Double(Self.height) * scale).rounded())
        let bytesPerRow = pixelWidth * ComparisonImage.bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * pixelHeight)
        pixels.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else { return }
            context.render(
                output,
                toBitmap: base,
                rowBytes: bytesPerRow,
                bounds: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight),
                format: .BGRA8,
                colorSpace: PaletteColor.sRGB
            )
        }
        return pixels
    }
}
