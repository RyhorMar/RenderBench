import BenchCore
import BenchRuntime

/// One vertex handed to `Chart`, already grouped so a break never becomes one.
///
/// Built once, in `SwiftChartsChartRenderer.encode(_:)`, rather than inside
/// `SwiftChartsChartView.body` — the same invariant every other backend's geometry keeps: work
/// that does not change between two draws of the same frame does not belong on the draw call's
/// path.
public struct PlottedMark: Sendable, Equatable, Identifiable {
    public let id: Int
    /// Groups marks into the `LineMark` series `Chart` must connect: one key per contiguous run
    /// of a series, `"<seriesIndex>-<runIndex>"`, so a break ends a line instead of being
    /// plotted as a point Swift Charts would then draw a segment through.
    public let seriesKey: String
    public let colour: PaletteColor
    public let x: Double
    public let y: Double

    public init(id: Int, seriesKey: String, colour: PaletteColor, x: Double, y: Double) {
        self.id = id
        self.seriesKey = seriesKey
        self.colour = colour
        self.x = x
        self.y = y
    }
}

/// Geometry for one frame, prepared before `SwiftChartsChartView` ever runs its `body`.
public struct SwiftChartsFrame {
    /// Rectangle `Chart` is padded to occupy, matching every other backend's plot exactly.
    public var plotRect: PlotRect
    /// The grid, axes and labels, laid out once for every backend to stroke.
    public var chrome: ChromeLayout
    /// Every mark `Chart` draws, already split at breaks and keyed by run.
    public var marks: [PlottedMark]
    /// Stroke width in points, taken from the spec.
    public var lineWidth: Double
    /// Series the preparation refused to draw, with the reason.
    public var failures: [SeriesFailure]
    /// Samples handed to this backend after downsampling.
    public var pointsSubmitted: Int
    /// Samples actually turned into a mark. Divergence from `pointsSubmitted` — by exactly the
    /// number of breaks — means the frame bought its time by dropping work.
    public var pointsDrawn: Int
    /// Nanoseconds spent grouping points into marks.
    public var encodeNs: UInt64

    public init() {
        self.plotRect = PlotRect(x: 0, y: 0, width: 0, height: 0)
        self.chrome = .empty
        self.marks = []
        self.lineWidth = 1
        self.failures = []
        self.pointsSubmitted = 0
        self.pointsDrawn = 0
        self.encodeNs = 0
    }
}
