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
        guard let canvas = BitmapCanvas(width: width, height: height) else { return nil }
        canvas.context.interpolationQuality = .none
        layer.render(in: canvas.context)
        return canvas.pixels()
    }
}
