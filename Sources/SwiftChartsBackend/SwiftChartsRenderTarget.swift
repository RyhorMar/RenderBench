import BenchCore
import BenchRuntime
import SwiftUI

/// Renders a prepared frame through the real `SwiftChartsChartView`, off screen, at the pinned
/// comparison format.
///
/// Nothing here draws directly: `ImageRenderer` runs the same `body` a screen would, which is the
/// only way to compare this backend honestly — `Chart` owns its own rasterisation, and a target
/// that reimplemented it would be testing the reimplementation, not the backend.
@MainActor
public enum SwiftChartsRenderTarget {
    /// Width in points of every comparison render.
    public static let width = ComparisonImage.width
    /// Height in points of every comparison render.
    public static let height = ComparisonImage.height

    /// Draws a prepared frame and returns raw premultiplied BGRA bytes.
    ///
    /// - Returns: `nil` when `ImageRenderer` produced no image, or when the bitmap it is copied
    ///   into could not be created — a fact about the host, not a rendering failure.
    public static func render(_ frame: PreparedFrame) -> [UInt8]? {
        let encoded = SwiftChartsChartRenderer.encode(frame)
        let view = SwiftChartsChartView(frame: encoded)
            .frame(width: CGFloat(width), height: CGFloat(height))
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: CGFloat(width), height: CGFloat(height))
        guard let cgImage = renderer.cgImage else { return nil }
        guard let canvas = BitmapCanvas(width: width, height: height) else { return nil }

        // `BitmapCanvas` flips its context so that path drawing in top-left coordinates lands
        // correctly — the convention every other render target in this package relies on. A
        // `CGImage` does not follow that convention: `draw(_:in:)` places its rows exactly as the
        // CTM dictates, with nothing image-specific correcting for a flipped destination, so an
        // already top-down image drawn straight into this context comes out mirrored top to
        // bottom. One more flip, local to this call, cancels the canvas's own and restores it
        // once the image is placed.
        canvas.context.saveGState()
        canvas.context.translateBy(x: 0, y: CGFloat(height))
        canvas.context.scaleBy(x: 1, y: -1)
        canvas.context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        canvas.context.restoreGState()
        return canvas.pixels()
    }
}
