import BenchCore
import BenchRuntime
import Foundation
import QuartzCore

/// The result of putting one prepared frame into the layer tree.
public struct CoreAnimationFrame: Sendable {
    /// Samples handed to the backend after reduction.
    public var pointsSubmitted: Int
    /// Samples actually turned into geometry.
    public var pointsDrawn: Int
    /// Shape layers carrying a series path. The Core Animation analogue of a draw call.
    public var shapeLayerCount: Int
    /// Animatable properties actually written this frame, excluding the paths.
    ///
    /// Reported rather than assumed: every such write marks a shape dirty and triggers an action
    /// lookup, and an earlier version rewrote colour, width and the hidden flag on every series
    /// every frame — about three thousand a second at 120 Hz — while its own documentation claimed
    /// only the path was replaced. A steady scene should settle at zero.
    public var styleWrites: Int
    /// Nanoseconds spent windowing, reducing and projecting — the shared preparation.
    public var prepareNs: UInt64
    /// Nanoseconds spent building paths and assigning them to layers.
    public var encodeNs: UInt64
    /// Series the preparation refused, with the reason.
    public var failures: [SeriesFailure]

    public init() {
        pointsSubmitted = 0
        pointsDrawn = 0
        shapeLayerCount = 0
        styleWrites = 0
        prepareNs = 0
        encodeNs = 0
        failures = []
    }
}

/// A layer tree that draws a prepared frame: a background, grid lines, axes and one shape layer
/// per series.
///
/// Layers are reused across frames and only their `path` is replaced. Recreating them would make
/// every frame pay for layer allocation and for the tree's re-composition, which measures the
/// allocator rather than the rendering method.
///
/// - Important: Use from the main thread, as `CALayer` itself requires. The type is deliberately
///   not main-actor isolated: `CALayer` declares its initialisers outside any actor, so a subclass
///   cannot isolate them, and annotating only the methods would promise an enforcement the
///   compiler cannot deliver.
public final class CoreAnimationChartLayer: CALayer {
    private let gridLayer = CAShapeLayer()
    private let axisLayer = CAShapeLayer()
    private var seriesLayers: [CAShapeLayer] = []
    /// Last colour and width written to each series layer, so an unchanged appearance is not
    /// rewritten. Every animatable write marks the shape dirty and triggers an action lookup, and
    /// a freshly built `CGColor` is never equal by identity to the last one — so without this the
    /// short-circuit that would skip the work can never fire.
    private var appliedStyle: [ObjectIdentifier: (colour: PaletteColor, width: Double)] = [:]

    /// Device pixels per point. **Must be set by the host** from the screen it draws on.
    ///
    /// A hand-allocated `CALayer` starts at 1.0 and `addSublayer` does not propagate the value, so
    /// left alone every shape here rasterises at a third of a 3x device's resolution: soft strokes,
    /// and — worse for this project — roughly a ninth of the render server's work, which would let
    /// this backend win a timing comparison it never actually ran.
    public var renderScale: CGFloat = 1 {
        didSet { applyScale() }
    }

    public override init() {
        super.init()
        commonSetup()
    }

    /// Core Animation's initialiser for a presentation copy.
    ///
    /// Documented to be used **only** to copy custom property values from `layer`. An earlier
    /// version ran the full setup here, which allocated two shape layers and attached them to
    /// every presentation copy the render server took, while leaving the copy's series layers
    /// empty and resetting its background to white.
    public override init(layer: Any) {
        super.init(layer: layer)
        if let source = layer as? CoreAnimationChartLayer {
            renderScale = source.renderScale
        }
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonSetup()
    }

    private func commonSetup() {
        gridLayer.fillColor = nil
        axisLayer.fillColor = nil
        // No frame has arrived yet to say otherwise, and a background left nil composites as
        // transparent — a mismatch against every reference image attributable to nothing about
        // rendering.
        backgroundColor = ChromeLayout.empty.background.cgColor
        for layer in [gridLayer, axisLayer] {
            suppressActions(on: layer)
            addSublayer(layer)
        }
        suppressActions(on: self)
        applyScale()
    }

    /// Turns off implicit animation as a property of the layer, not of one call site.
    ///
    /// The transaction inside ``update(with:)`` protects only what happens there. A resize, a
    /// layout pass, or any host code touching a stroke colour outside it would otherwise get the
    /// default quarter-second animation back — a chart that visibly slides into place on rotation.
    private func suppressActions(on layer: CALayer) {
        layer.actions = [
            "path": NSNull(), "bounds": NSNull(), "position": NSNull(), "frame": NSNull(),
            "strokeColor": NSNull(), "lineWidth": NSNull(), "hidden": NSNull(),
            "backgroundColor": NSNull(), "contents": NSNull(), "sublayers": NSNull(),
        ]
    }

    private func applyScale() {
        contentsScale = renderScale
        for layer in sublayers ?? [] { layer.contentsScale = renderScale }
    }

    /// Keeps every sublayer covering the whole chart.
    ///
    /// Without this each sublayer keeps `bounds == .zero`, and the paths draw only because a shape
    /// layer does not clip to its bounds and `masksToBounds` defaults to false — correct by the
    /// coincidence of two defaults. The render server sizes backing stores and computes dirty
    /// rects from that geometry, so it would be reasoning about ten zero-area boxes at the origin.
    public override func layoutSublayers() {
        super.layoutSublayers()
        for layer in sublayers ?? [] {
            layer.frame = bounds
            layer.contentsScale = renderScale
        }
    }

    /// Puts a prepared frame into the tree.
    ///
    /// - Returns: what it cost, for the metrics sink.
    @discardableResult
    public func update(with prepared: PreparedFrame) -> CoreAnimationFrame {
        var result = CoreAnimationFrame()
        result.prepareNs = prepared.prepareNs
        result.pointsSubmitted = prepared.pointsSubmitted
        result.failures = prepared.failures

        let plot = prepared.plotRect
        guard plot.isDrawable else { return result }

        let clock = ContinuousClock()
        var drawn = 0
        var styleWrites = 0

        let elapsed = clock.measure {
            // Belt to the per-layer `actions` braces. `CAShapeLayer.path` is animatable but
            // creates no implicit animation of its own — the earlier comment here claimed
            // otherwise — so what this actually protects is the stroke colour, the line width and
            // the hidden flag, each of which would cross-fade over a quarter of a second and let
            // the reader see a blend of two instants.
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            defer { CATransaction.commit() }

            backgroundColor = prepared.chrome.background.cgColor

            let gridLines = prepared.chrome.lines.dropLast(2)
            let axisLines = prepared.chrome.lines.suffix(2)
            gridLayer.path = chromePath(gridLines)
            axisLayer.path = chromePath(axisLines)
            applyChromeStyle(gridLines, to: gridLayer)
            applyChromeStyle(axisLines, to: axisLayer)

            growSeriesLayers(to: prepared.series.count)
            for (position, series) in prepared.series.enumerated() {
                let layer = seriesLayers[position]
                // Only on change. Rewriting an identical colour and width every frame was around
                // a thousand CGColor allocations and three thousand animatable writes a second at
                // 120 Hz with eight series — all charged to a backend whose number is meant to
                // stand for the rendering method.
                let key = ObjectIdentifier(layer)
                let wanted = (colour: series.colour, width: prepared.lineWidth)
                if appliedStyle[key]?.colour != wanted.colour
                    || appliedStyle[key]?.width != wanted.width {
                    layer.strokeColor = series.colour.cgColor
                    layer.lineWidth = CGFloat(prepared.lineWidth)
                    appliedStyle[key] = wanted
                    styleWrites += 2
                }
                if layer.isHidden {
                    layer.isHidden = false
                    styleWrites += 1
                }

                let path = CGMutablePath()
                var penIsDown = false
                for point in series.points {
                    guard !point.isBreak else {
                        penIsDown = false
                        continue
                    }
                    let location = CGPoint(
                        x: plot.minX + point.x * plot.width,
                        y: plot.maxY - point.y * plot.height
                    )
                    if penIsDown {
                        path.addLine(to: location)
                    } else {
                        path.move(to: location)
                        penIsDown = true
                    }
                    drawn += 1
                }
                layer.path = path
            }
            for position in prepared.series.count..<seriesLayers.count
            where !seriesLayers[position].isHidden {
                seriesLayers[position].isHidden = true
                seriesLayers[position].path = nil
                styleWrites += 1
            }
        }

        result.pointsDrawn = drawn
        result.shapeLayerCount = prepared.series.count
        result.styleWrites = styleWrites
        result.encodeNs = elapsed.nanoseconds
        return result
    }

    /// Adds shape layers as the series count grows, and keeps them.
    ///
    /// Never shrinks: a scene that alternates between eight series and one would otherwise pay for
    /// layer creation on every switch. Surplus layers are hidden with a nil path, which costs
    /// nothing to composite.
    private func growSeriesLayers(to count: Int) {
        while seriesLayers.count < count {
            let layer = CAShapeLayer()
            layer.fillColor = nil
            layer.lineCap = .round
            // Bevel, not round. At roughly one point between vertices a round join builds arc
            // geometry nobody can see; the Canvas backend makes the same choice, so the two are
            // comparable rather than differing by stroke style.
            layer.lineJoin = .bevel
            layer.frame = bounds
            layer.contentsScale = renderScale
            suppressActions(on: layer)
            addSublayer(layer)
            seriesLayers.append(layer)
        }
    }

    /// Sets a shape layer's colour and width from the first line of its group, unconditionally.
    ///
    /// Not `if let style = lines.first`: a group that goes from non-empty to empty (its path
    /// already cleared to nothing by ``chromePath(_:)``) must not leave the layer's colour and
    /// width describing a path that is no longer there.
    private func applyChromeStyle(_ lines: some Collection<ChromeLine>, to layer: CAShapeLayer) {
        layer.lineWidth = CGFloat(lines.first?.width ?? 0)
        layer.strokeColor = lines.first?.colour.cgColor
    }

    /// Builds one path stroking each line independently.
    private func chromePath(_ lines: some Sequence<ChromeLine>) -> CGMutablePath {
        let path = CGMutablePath()
        for line in lines {
            path.move(to: CGPoint(x: line.x0, y: line.y0))
            path.addLine(to: CGPoint(x: line.x1, y: line.y1))
        }
        return path
    }

}
