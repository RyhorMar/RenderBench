import BenchCore
import BenchRuntime
import CoreGraphics
import Foundation
import Metal
import SceneKit

#if canImport(UIKit)
import UIKit
#else
// `SCNRenderer.snapshot(atTime:with:antialiasingMode:)` returns `UIImage` on iOS and `NSImage` on
// macOS — the one place in this backend where the two platforms hand back genuinely different
// types rather than the same Metal or Core Graphics value either way. `swift test` runs this exact
// target on macOS, so both sides need a way to reach the `CGImage` underneath; `AppKit` supplies it
// here for exactly that one call and nothing else.
import AppKit
#endif

/// Renders a prepared frame into a bitmap off screen, through the same node tree and camera
/// ``SceneKitRenderer`` puts on screen, at the pinned comparison format.
public final class SceneKitRenderTarget {
    /// Width in points. Pixels are this times the scale.
    public static let width = ComparisonImage.width
    /// Height in points.
    public static let height = ComparisonImage.height

    private let renderer: SCNRenderer

    /// - Returns: `nil` when the host has no Metal device, which is a fact about the host and not
    ///   a failure of the backend — a caller in a test suite should skip, not fail.
    public init?() {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        renderer = SCNRenderer(device: device, options: nil)
    }

    /// Draws a frame and returns raw premultiplied BGRA bytes, `width * height * 4 * scale²`.
    public func render(_ frame: PreparedFrame, scale: Double = 1) throws(SceneKitRendererError) -> [UInt8] {
        let scene = SCNScene()
        scene.background.contents = frame.chrome.background.cgColor
        let cameraNode = SceneKitChartGeometry.makeCamera()
        SceneKitChartGeometry.positionCamera(cameraNode, for: frame)
        scene.rootNode.addChildNode(cameraNode)
        scene.rootNode.addChildNode(SceneKitChartGeometry.buildContent(frame).node)

        renderer.scene = scene
        renderer.pointOfView = cameraNode

        let pixelWidth = Int((Double(Self.width) * scale).rounded())
        let pixelHeight = Int((Double(Self.height) * scale).rounded())
        let size = CGSize(width: pixelWidth, height: pixelHeight)
        guard let cgImage = cgImage(from: renderer.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X))
        else { throw .noSnapshot }
        guard let canvas = BitmapCanvas(width: pixelWidth, height: pixelHeight) else { throw .noSnapshot }

        // `BitmapCanvas` flips its context so that geometry drawn in top-left coordinates lands
        // correctly, the convention every render target in this package relies on. The snapshot is
        // an ordinary top-down image, not flipped for that convention, so drawing it straight into
        // an already-flipped context mirrors it top to bottom; this second, local flip cancels the
        // canvas's own and restores it once the image is placed — the same correction
        // `ShapePathRenderTarget` applies to `ImageRenderer`'s `CGImage` for the same reason.
        canvas.context.saveGState()
        canvas.context.translateBy(x: 0, y: CGFloat(pixelHeight))
        canvas.context.scaleBy(x: 1, y: -1)
        canvas.context.draw(cgImage, in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        canvas.context.restoreGState()
        return canvas.pixels()
    }
}

#if canImport(UIKit)
private func cgImage(from image: UIImage) -> CGImage? { image.cgImage }
#else
private func cgImage(from image: NSImage) -> CGImage? {
    var rect = CGRect(origin: .zero, size: image.size)
    return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
}
#endif
