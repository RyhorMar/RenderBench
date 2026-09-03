import BenchCore
import BenchDownsampling

/// Everything a line chart needs to be drawn, and nothing that belongs to another chart family.
///
/// One spec per family rather than one spec with optional fields for all of them: a single type
/// covering strip charts and heat maps would carry a colour ramp that a line chart ignores and a
/// line width that a raster ignores, and every backend would have to decide which halves to honour.
public struct LineChartSpec: Sendable {
    /// Indices of the series to draw, in draw order.
    public var series: [Int]
    /// How the series are reduced to what the display can resolve.
    public var policy: DownsamplePolicy
    /// Stroke width in points.
    public var lineWidth: Double
    /// Draw axes, ticks and labels.
    public var showsAxes: Bool
    /// Target number of labels per axis. Honoured only as far as the axis can hold them.
    public var tickTarget: Int

    public init(
        series: [Int],
        policy: DownsamplePolicy = .minMax,
        lineWidth: Double = 1.5,
        showsAxes: Bool = true,
        tickTarget: Int = 6
    ) {
        self.series = series
        self.policy = policy
        self.lineWidth = lineWidth
        self.showsAxes = showsAxes
        self.tickTarget = tickTarget
    }
}
