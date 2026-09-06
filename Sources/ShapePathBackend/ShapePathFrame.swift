import BenchCore
import BenchRuntime
import SwiftUI

/// One series' geometry, already split at its breaks into the shape this segment's
/// `PolylineShape` accepts.
public struct ShapePathSeries {
    /// Groups this series with its own past and future frames; identity `ForEach` keys on, so the
    /// `PolylineShape` view SwiftUI already has for series 2 stays series 2's view across ticks
    /// rather than being torn down and rebuilt under a positional key.
    public let index: Int
    public let colour: PaletteColor
    /// Absolute plot-space coordinates. See `PolylineShape.points`.
    public let points: [CGPoint]
    /// See `PolylineShape.breaks`.
    public let breaks: Set<Int>

    public init(index: Int, colour: PaletteColor, points: [CGPoint], breaks: Set<Int>) {
        self.index = index
        self.colour = colour
        self.points = points
        self.breaks = breaks
    }
}

/// Geometry for one frame, prepared before `ShapePathChartView` ever runs its `body`.
///
/// `drawCalls` is not a stored property here, unlike `CanvasFrame`: this backend hands SwiftUI a
/// `Shape` value and never itself calls a drawing API, so there is no submission count for this
/// type to carry. `ShapePathRenderer.encode(_:)` reports that directly as `nil`.
public struct ShapePathFrame {
    /// Rectangle the series are drawn inside, in the same absolute coordinates as `points`.
    public var plotRect: CGRect
    /// The grid, axes and labels, laid out once for every backend to stroke.
    public var chrome: ChromeLayout
    /// One shape's worth of geometry per series, in draw order.
    public var series: [ShapePathSeries]
    /// Stroke width in points, taken from the spec.
    public var lineWidth: Double
    /// Series the preparation refused to draw, with the reason.
    public var failures: [SeriesFailure]
    /// Samples handed to this backend after downsampling.
    public var pointsSubmitted: Int
    /// Samples actually turned into a point. Divergence from `pointsSubmitted` — by exactly the
    /// number of breaks — means the frame bought its time by dropping work.
    public var pointsDrawn: Int
    /// Nanoseconds spent turning prepared points into per-series geometry.
    public var encodeNs: UInt64

    public init() {
        self.plotRect = .zero
        self.chrome = .empty
        self.series = []
        self.lineWidth = 1
        self.failures = []
        self.pointsSubmitted = 0
        self.pointsDrawn = 0
        self.encodeNs = 0
    }
}
