import BenchCore
import BenchRuntime
import SwiftUI

/// One series' buffers for this method: its colour, and one packed run per `ShaderChartView`
/// invocation of `chart_line`.
public struct ShaderSeriesBuffers {
    /// Groups this series with its own past and future frames; identity `ForEach` keys on, so a
    /// series' `colorEffect` view stays that series' view across ticks instead of being torn down
    /// and rebuilt under a positional key.
    public let index: Int
    public let colour: PaletteColor
    /// One `Data` buffer per contiguous run — see `ShaderLineBuffers.runs(for:plot:)`.
    public let runs: [Data]

    public init(index: Int, colour: PaletteColor, runs: [Data]) {
        self.index = index
        self.colour = colour
        self.runs = runs
    }
}

/// Geometry for one frame, prepared before `ShaderChartView` ever runs its `body`.
///
/// `drawCalls` is not a stored property here, the same as `ShapePathFrame`: this backend hands
/// SwiftUI a `Shader` value per run and never itself calls a drawing API, so there is no submission
/// count for this type to carry. `ShaderRenderer.encode(_:)` reports that directly as `nil`.
public struct ShaderFrame {
    /// Rectangle the series are drawn inside, in the same absolute coordinates `chrome` uses.
    public var plotRect: CGRect
    /// The grid, axes and labels, laid out once for every backend to stroke.
    public var chrome: ChromeLayout
    /// One buffer set per series, in draw order.
    public var series: [ShaderSeriesBuffers]
    /// Stroke width in points, taken from the spec; `chart_line` receives half of it.
    public var lineWidth: Double
    /// Series the preparation refused to draw, with the reason.
    public var failures: [SeriesFailure]
    /// Samples handed to this backend after downsampling.
    public var pointsSubmitted: Int
    /// Samples actually turned into a point. Divergence from `pointsSubmitted` — by exactly the
    /// number of breaks — means the frame bought its time by dropping work.
    public var pointsDrawn: Int
    /// Nanoseconds spent turning prepared points into per-run buffers.
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
