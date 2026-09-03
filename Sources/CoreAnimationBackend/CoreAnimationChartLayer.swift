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

    /// Background fill, matching the offscreen reference so the two backends can be compared.
    public var backgroundFill = PaletteColor(red: 1, green: 1, blue: 1)

    public override init() {
        super.init()
        commonSetup()
    }

    public override init(layer: Any) {
        super.init(layer: layer)
        commonSetup()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonSetup()
    }

    private func commonSetup() {
        // Every layer here is drawn by an explicit path assignment, never by `draw(in:)`, so
        // there is nothing for the layer to redraw on its own.
        needsDisplayOnBoundsChange = false
        gridLayer.fillColor = nil
        gridLayer.lineWidth = 0.5
        gridLayer.strokeColor = cgColour(PaletteColor(red: 0.8, green: 0.8, blue: 0.8))
        axisLayer.fillColor = nil
        axisLayer.lineWidth = 1
        axisLayer.strokeColor = cgColour(PaletteColor(red: 0.4, green: 0.4, blue: 0.4))
        addSublayer(gridLayer)
        addSublayer(axisLayer)
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

        let elapsed = clock.measure {
            // Implicit animations are the default for every animatable layer property, so without
            // this each new path would cross-fade into the last over a quarter of a second. On a
            // chart that is both wrong — the reader sees a blend of two instants — and expensive,
            // since the layer keeps both geometries alive for the duration.
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            defer { CATransaction.commit() }

            backgroundColor = cgColour(backgroundFill)

            let grid = CGMutablePath()
            for tick in prepared.yTicks {
                let y = plot.maxY - tick.position * plot.height
                grid.move(to: CGPoint(x: plot.minX, y: y))
                grid.addLine(to: CGPoint(x: plot.maxX, y: y))
            }
            gridLayer.path = grid

            let axes = CGMutablePath()
            axes.move(to: CGPoint(x: plot.minX, y: plot.minY))
            axes.addLine(to: CGPoint(x: plot.minX, y: plot.maxY))
            axes.addLine(to: CGPoint(x: plot.maxX, y: plot.maxY))
            axisLayer.path = axes

            growSeriesLayers(to: prepared.series.count)
            for (position, series) in prepared.series.enumerated() {
                let layer = seriesLayers[position]
                layer.strokeColor = cgColour(series.colour)
                layer.lineWidth = CGFloat(prepared.lineWidth)
                layer.isHidden = false

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
            for position in prepared.series.count..<seriesLayers.count {
                seriesLayers[position].isHidden = true
                seriesLayers[position].path = nil
            }
        }

        result.pointsDrawn = drawn
        result.shapeLayerCount = prepared.series.count
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
            layer.lineJoin = .round
            addSublayer(layer)
            seriesLayers.append(layer)
        }
    }

    private func cgColour(_ colour: PaletteColor) -> CGColor {
        // CGColor takes encoded sRGB; linear components here would darken every stroke, and the
        // comparison against the Canvas backend would fail for a reason that has nothing to do
        // with either rendering method.
        let encoded = colour.encodedSRGB
        return CGColor(
            red: CGFloat(encoded.red),
            green: CGFloat(encoded.green),
            blue: CGFloat(encoded.blue),
            alpha: 1
        )
    }
}
