import BenchCore
import BenchRuntime
import SwiftUI

/// Renders a prepared frame through the real `ShaderChartView`, off screen, at the pinned
/// comparison format.
///
/// This type lives at the package level, the same as `ShapePathRenderTarget`, so the equivalence
/// test that actually judges it does not have to reimplement the render path in `Demo/Tests` — it
/// only has to call this. What it cannot do from here is mean anything: `ShaderLibrary.default`
/// resolves `chart_line` from the main bundle of whatever process calls `render(_:)`, and no bundle
/// `swift test` runs in has compiled `Demo/Sources/Shaders/ChartLine.metal` into it. Calling this
/// from a package test would return bytes, not a failure — a `Rectangle` whose colour effect never
/// resolved, silently. Only a caller running inside the demo app's own test bundle can trust what
/// comes back, which is why that caller lives in `RenderBenchDemoTests` rather than here.
@MainActor
public enum ShaderRenderTarget {
    /// Width in points of every comparison render.
    public static let width = ComparisonImage.width
    /// Height in points of every comparison render.
    public static let height = ComparisonImage.height

    /// Draws a prepared frame and returns raw premultiplied BGRA bytes.
    ///
    /// - Returns: `nil` when `ImageRenderer` produced no image, or when the bitmap it is copied
    ///   into could not be created — a fact about the host, not a rendering failure.
    public static func render(_ frame: PreparedFrame) -> [UInt8]? {
        let encoded = ShaderChartRenderer.encode(frame)
        let view = ShaderChartView(frame: encoded)
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
        // bottom. One more flip, local to this call, cancels the canvas's own and restores it once
        // the image is placed.
        canvas.context.saveGState()
        canvas.context.translateBy(x: 0, y: CGFloat(height))
        canvas.context.scaleBy(x: 1, y: -1)
        canvas.context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        canvas.context.restoreGState()
        return canvas.pixels()
    }
}
