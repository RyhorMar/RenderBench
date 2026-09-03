import BenchCore
import SwiftUI

/// A tick already projected into the plot, as a fraction of the axis from its origin.
///
/// The position is computed by the same `AxisScale` that placed the samples. Handing the view raw
/// data values instead invites it to derive a second projection of its own, which is how an axis
/// ends up disagreeing with the curve it annotates.
public struct PlottedTick: Sendable, Equatable {
    /// Position along the axis in `0...1`, measured from the axis origin.
    public let position: Double
    /// Rendered text. Empty for minor ticks, which are drawn but not labelled.
    public let label: String

    public init(position: Double, label: String) {
        self.position = position
        self.label = label
    }
}

/// A series that could not be drawn, and why.
///
/// Carried on the frame rather than thrown, because one refused series must not cost the reader
/// the other seven — but it must not be silent either. A backend that swallows a refusal renders
/// a chart with a series missing and no way to find out.
public struct SeriesFailure: Sendable, Equatable {
    public let seriesIndex: Int
    public let error: ChartError

    public init(seriesIndex: Int, error: ChartError) {
        self.seriesIndex = seriesIndex
        self.error = error
    }
}

/// Geometry for one frame, prepared before the draw call rather than inside it.
///
/// `Canvas` invites the opposite — windowing, downsampling and path building all inside the draw
/// closure — and that is precisely the shape this project exists to argue against: it puts data
/// preparation on the frame's critical path and makes the two costs impossible to tell apart in a
/// measurement.
public struct CanvasFrame {
    /// One stroked path per series, in draw order, with the colour it is drawn in.
    public var strokes: [(colour: PaletteColor, path: Path)]
    /// Ticks along the carrier axis, already projected.
    public var xTicks: [PlottedTick]
    /// Ticks along the value axis, already projected.
    public var yTicks: [PlottedTick]
    /// Rectangle the series are drawn inside, excluding axis labels.
    public var plotRect: CGRect
    /// Stroke width in points, taken from the spec.
    public var lineWidth: Double
    /// Series the renderer refused to draw, with the reason.
    public var failures: [SeriesFailure]
    /// Samples handed to the renderer after downsampling.
    public var pointsSubmitted: Int
    /// Samples actually turned into geometry. Divergence from `pointsSubmitted` means the frame
    /// bought its time by dropping work.
    public var pointsDrawn: Int
    /// Nanoseconds spent windowing and downsampling.
    public var prepareNs: UInt64
    /// Nanoseconds spent building geometry.
    public var encodeNs: UInt64

    public init() {
        self.strokes = []
        self.xTicks = []
        self.yTicks = []
        self.plotRect = .zero
        self.lineWidth = 1
        self.failures = []
        self.pointsSubmitted = 0
        self.pointsDrawn = 0
        self.prepareNs = 0
        self.encodeNs = 0
    }
}
