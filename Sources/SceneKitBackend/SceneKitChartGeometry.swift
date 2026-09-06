import BenchCore
import BenchRuntime
import CoreGraphics
import Foundation
import SceneKit

/// Turns a prepared frame into `.line`-primitive nodes, and the orthographic camera that must
/// view them for the projected image to line up with every other backend's frame.
///
/// Building `SCNGeometry` touches no Metal device — unlike the on-screen and off-screen surfaces
/// that draw it, everything here is plain data, so it is testable on a host with no GPU at all.
public enum SceneKitChartGeometry {
    /// A camera positioned to look straight down the -Z axis at whatever content sits at `z == 0`
    /// — the plane every node this type builds is placed on — with no rotation of its own.
    ///
    /// `orthographicScale` and the node's position are not set here: both depend on the frame
    /// being drawn, and are recomputed every ``positionCamera(_:for:)`` call rather than once at
    /// construction, since the canvas a scene draws can change size between frames.
    public static func makeCamera() -> SCNNode {
        let camera = SCNCamera()
        camera.usesOrthographicProjection = true
        camera.zNear = 1
        camera.zFar = 1_000
        let node = SCNNode()
        node.camera = camera
        return node
    }

    /// Points the camera at the centre of `frame`'s canvas and scales it to show the canvas
    /// exactly — one SceneKit unit per point, matching the point-space coordinates every node
    /// below is built in.
    ///
    /// `orthographicScale` is defined as half the projected height; setting it to half the canvas
    /// height and centring the camera on the canvas is what makes a camera unrotated on its own
    /// -Z axis show precisely `canvasWidth` × `canvasHeight` points, provided the destination the
    /// camera renders into shares the canvas's aspect ratio — true of both this backend's
    /// `SCNView`, sized by its host to the same frame the scene was prepared for, and its offscreen
    /// render target, sized to the same pinned comparison format the geometry itself was built at.
    public static func positionCamera(_ node: SCNNode, for frame: PreparedFrame) {
        let canvas = canvasSize(for: frame)
        node.camera?.orthographicScale = canvas.height / 2
        node.position = SCNVector3(Float(canvas.width / 2), Float(canvas.height / 2), 100)
    }

    /// The frame's own canvas, in points — width and height, not merely the plot rectangle.
    ///
    /// `PreparedFrame` carries `plotRect` but no canvas size of its own; `FramePreparation` built
    /// that rectangle by subtracting its four fixed insets from the canvas it was given, so the
    /// canvas is recovered by adding them back rather than needing a field nothing else in this
    /// project stores.
    public static func canvasSize(for frame: PreparedFrame) -> (width: Double, height: Double) {
        (
            frame.plotRect.maxX + FramePreparation.rightInset,
            frame.plotRect.maxY + FramePreparation.bottomInset
        )
    }

    /// Builds one child node per chrome line and one per series, and returns the node holding them
    /// plus the samples this frame actually turned into geometry.
    ///
    /// The count excludes breaks for the same reason `MetalRenderer.samplesDrawn` does: a lone
    /// point between two breaks contributes a vertex but no drawable segment, so neither a raw
    /// point count nor a segment count answers "how many samples did this frame draw."
    public static func buildContent(_ frame: PreparedFrame) -> (node: SCNNode, pointsDrawn: Int) {
        let root = SCNNode()
        guard frame.plotRect.isDrawable else { return (root, 0) }
        let canvasHeight = canvasSize(for: frame).height

        for line in frame.chrome.lines {
            root.addChildNode(chromeNode(line, canvasHeight: canvasHeight))
        }

        var drawn = 0
        for series in frame.series {
            let (node, count) = seriesNode(series, plot: frame.plotRect, canvasHeight: canvasHeight)
            root.addChildNode(node)
            drawn += count
        }
        return (root, drawn)
    }

    /// Flips a point-space y coordinate — origin top left, increasing downward, the convention
    /// every other backend's geometry shares — into SceneKit's right-handed, y-up world space.
    private static func worldY(_ pointSpaceY: Double, canvasHeight: Double) -> Float {
        Float(canvasHeight - pointSpaceY)
    }

    /// One chrome line as a single two-vertex `.line` element, in its own colour.
    private static func chromeNode(_ line: ChromeLine, canvasHeight: Double) -> SCNNode {
        let vertices = [
            SCNVector3(Float(line.x0), worldY(line.y0, canvasHeight: canvasHeight), 0),
            SCNVector3(Float(line.x1), worldY(line.y1, canvasHeight: canvasHeight), 0),
        ]
        let element = SCNGeometryElement(indices: [Int32(0), Int32(1)], primitiveType: .line)
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices)], elements: [element])
        geometry.firstMaterial = constantMaterial(colour: line.colour)
        return SCNNode(geometry: geometry)
    }

    /// One series as a shared vertex buffer with one `.line` element per unbroken run.
    ///
    /// A break ends the run before it and starts a new one: the point marked `isBreak` is never
    /// itself a vertex, and no element's index pairs cross from one run into the next — the same
    /// treatment `CoreGraphicsReference.path(for:in:)` gives a break, with a new `SCNGeometryElement`
    /// standing in for that path's `move(to:)`.
    private static func seriesNode(
        _ series: PreparedSeries, plot: PlotRect, canvasHeight: Double
    ) -> (node: SCNNode, pointsDrawn: Int) {
        var vertices: [SCNVector3] = []
        var elements: [SCNGeometryElement] = []
        var runStart = 0
        var drawn = 0

        func closeRun(endExclusive: Int) {
            defer { runStart = endExclusive }
            guard endExclusive - runStart >= 2 else { return }
            var indices: [Int32] = []
            indices.reserveCapacity((endExclusive - runStart - 1) * 2)
            for index in runStart..<(endExclusive - 1) {
                indices.append(Int32(index))
                indices.append(Int32(index + 1))
            }
            elements.append(SCNGeometryElement(indices: indices, primitiveType: .line))
        }

        for point in series.points {
            guard !point.isBreak else {
                closeRun(endExclusive: vertices.count)
                continue
            }
            let x = plot.minX + point.x * plot.width
            let y = plot.maxY - point.y * plot.height
            vertices.append(SCNVector3(Float(x), worldY(y, canvasHeight: canvasHeight), 0))
            drawn += 1
        }
        closeRun(endExclusive: vertices.count)

        let node = SCNNode()
        guard !elements.isEmpty else { return (node, drawn) }
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices)], elements: elements)
        geometry.firstMaterial = constantMaterial(colour: series.colour)
        node.geometry = geometry
        return (node, drawn)
    }

    /// A material lit only by its own `diffuse` colour, unaffected by any light in the scene —
    /// this backend adds none, so any other lighting model would render every line black.
    ///
    /// `diffuse.contents` takes `colour.cgColor` directly rather than a `UIColor` wrapping it: the
    /// two are the same colour, since `UIColor(cgColor:)` performs no conversion of its own, and
    /// `SCNMaterialProperty.contents` accepts a `CGColor` on every platform this package targets —
    /// unlike `UIColor`, which does not exist on macOS, where `swift test` runs this exact code.
    private static func constantMaterial(colour: PaletteColor) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = colour.cgColor
        return material
    }
}
