import BenchCore
import BenchRuntime
import CoreGraphics
import Foundation
import QuartzCore

/// Renders the layer tree off screen, at the same pinned configuration every backend is compared
/// at.
///
/// The point is not a picture but a comparison: this is how a Core Animation frame is put next to
/// a Canvas frame and judged the same or not. Anything that differs between the two targets —
/// size, colour space, antialiasing — would show up as a rendering difference that is really a
/// difference in how they were photographed.
public enum CoreAnimationRenderTarget {
    public static let width = 1_024
    public static let height = 768
    public static let bytesPerPixel = 4

    /// Draws a prepared frame through the layer tree and returns raw premultiplied BGRA bytes.
    public static func render(_ prepared: PreparedFrame) -> [UInt8]? {
        let layer = CoreAnimationChartLayer()
        layer.frame = CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))
        layer.update(with: prepared)
        return render(layer)
    }

    /// Draws an already-populated layer tree.
    public static func render(_ layer: CALayer) -> [UInt8]? {
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)

        let created: CGContext? = pixels.withUnsafeMutableBytes { raw in
            CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue
            )
        }
        guard let context = created else { return nil }

        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)
        context.interpolationQuality = .none
        // `CALayer.render(in:)` draws in the layer's own coordinate space, whose origin is at the
        // top left; the bitmap's is at the bottom left. Flipping here rather than in the geometry
        // keeps both backends drawing from one set of coordinates.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)

        layer.render(in: context)
        return pixels
    }
}
