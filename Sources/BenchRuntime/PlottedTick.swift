import BenchCore

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
