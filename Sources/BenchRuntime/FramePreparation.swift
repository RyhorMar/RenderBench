import BenchCore
import BenchDownsampling
import BenchScales
import Foundation

/// Rectangle the series are drawn inside, in points, with the origin at the top left.
///
/// Its own type rather than `CGRect`: this module has no business importing a graphics framework
/// for four numbers, and every backend converts to whatever its own layer wants anyway.
public struct PlotRect: Sendable, Equatable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var minX: Double { x }
    public var minY: Double { y }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    /// Whether there is room to draw anything meaningful.
    public var isDrawable: Bool { width > 1 && height > 1 }
}

/// One point of a reduced series, already projected into `0...1` on both axes.
///
/// Projection happens here, once, for every backend. If each backend projected for itself, two of
/// them could disagree about where a sample belongs while both drew a plausible chart — and the
/// equivalence check would be comparing two different questions rather than two answers.
public struct PlottedPoint: Sendable, Equatable {
    /// Position along the carrier axis, `0` at the window's start.
    public let x: Double
    /// Position along the value axis, `0` at the domain's bottom.
    public let y: Double
    /// True where the series has no measurement and the line must break.
    public let isBreak: Bool

    public init(x: Double, y: Double, isBreak: Bool) {
        self.x = x
        self.y = y
        self.isBreak = isBreak
    }
}

/// One series, reduced and projected, with the colour it is drawn in.
public struct PreparedSeries: Sendable {
    public let index: Int
    public let colour: PaletteColor
    public let points: [PlottedPoint]

    public init(index: Int, colour: PaletteColor, points: [PlottedPoint]) {
        self.index = index
        self.colour = colour
        self.points = points
    }
}

/// Everything a backend needs to draw one frame, and nothing about how to draw it.
///
/// The split is the whole basis of the comparison. Windowing, downsampling and projection are
/// identical for every backend by construction; what differs is the geometry each one builds from
/// this and the machinery it uses to put that geometry on screen. Timing the two separately is
/// what makes "this backend is faster" a statement about the backend rather than about whoever
/// wrote its data path.
public struct PreparedFrame: Sendable {
    public var plotRect: PlotRect
    public var series: [PreparedSeries]
    public var xTicks: [PlottedTick]
    public var yTicks: [PlottedTick]
    public var lineWidth: Double
    /// Series the preparation refused, with the reason. Reported, never silently omitted.
    public var failures: [SeriesFailure]
    /// Samples handed to the backend after reduction.
    public var pointsSubmitted: Int
    /// Nanoseconds spent windowing, reducing and projecting.
    public var prepareNs: UInt64
    /// The grid, axes and labels, laid out once for every backend to stroke.
    public var chrome: ChromeLayout = .empty
    /// Device scale this frame was prepared at, e.g. `3` on a 3x display.
    ///
    /// A retained-mode backend needs it for `contentsScale`: leaving that at the default rasterises
    /// at a fraction of the device's resolution and wins a timing comparison it never actually ran.
    /// A backend that builds its own vertex buffer needs it to size that buffer in device pixels.
    public var scale: Double

    public init(plotRect: PlotRect = PlotRect(x: 0, y: 0, width: 0, height: 0)) {
        self.plotRect = plotRect
        self.series = []
        self.xTicks = []
        self.yTicks = []
        self.lineWidth = 1
        self.failures = []
        self.pointsSubmitted = 0
        self.prepareNs = 0
        self.scale = 1
    }
}

/// Turns provider data into a projected frame, once per frame, for whichever backend draws it.
public enum FramePreparation {
    /// Space reserved for axis labels, in points. Shared, so that two backends do not compare
    /// charts of different sizes and call the difference a rendering difference.
    public static let leftInset = 52.0
    public static let bottomInset = 22.0
    public static let topInset = 10.0
    public static let rightInset = 12.0

    /// Windows, reduces and projects every series in the spec.
    ///
    /// - Parameters:
    ///   - scratch: Reused reduction buffer. Cleared on entry and read in place, never copied out.
    /// - Complexity: O(*n*) in the samples inside the window.
    public static func prepare(
        provider: some ChartDataProvider,
        spec: LineChartSpec,
        window: ClosedRange<Carrier>,
        yDomain: ClosedRange<Double>,
        size: (width: Double, height: Double),
        chrome: ChartChrome,
        scale: Double,
        dark: Bool,
        measuring: some TextMeasuring,
        scratch: inout [Sample]
    ) -> PreparedFrame {
        let plot = PlotRect(
            x: leftInset,
            y: topInset,
            width: max(0, size.width - leftInset - rightInset),
            height: max(0, size.height - topInset - bottomInset)
        )
        var frame = PreparedFrame(plotRect: plot)
        frame.lineWidth = spec.lineWidth
        frame.scale = scale
        guard plot.isDrawable, window.upperBound > window.lowerBound else { return frame }

        let xScale = TimeScale(domain: window)
        let yScale = LinearScale(domain: yDomain)
        // One target point per horizontal point of the plot. Asking for more than the display can
        // resolve is work whose result nobody can see.
        let target = max(2, Int(plot.width))

        let clock = ContinuousClock()
        var elapsed = Duration.zero

        for seriesIndex in spec.series {
            guard seriesIndex < provider.seriesCount else { continue }
            var failure: ChartError?
            var points: [PlottedPoint] = []

            elapsed += clock.measure {
                provider.withSeries(seriesIndex, in: window) { slice in
                    do {
                        try downsample(
                            slice,
                            to: target,
                            policy: spec.policy,
                            xScale: xScale,
                            yScale: yScale,
                            into: &scratch
                        )
                    } catch let error as ChartError {
                        failure = error
                    } catch {
                        failure = .emptyDomain
                    }
                }
                guard failure == nil else { return }

                points.reserveCapacity(scratch.count)
                for sample in scratch {
                    if sample.value.isNaN {
                        points.append(PlottedPoint(x: 0, y: 0, isBreak: true))
                    } else {
                        points.append(
                            PlottedPoint(
                                x: xScale.map(sample.carrier).normalised,
                                y: yScale.map(sample.value).normalised,
                                isBreak: false
                            )
                        )
                    }
                }
            }

            if let failure {
                frame.failures.append(SeriesFailure(seriesIndex: seriesIndex, error: failure))
                continue
            }
            frame.pointsSubmitted += points.count
            frame.series.append(
                PreparedSeries(
                    index: seriesIndex,
                    colour: Palette.colour(forSeries: seriesIndex, dark: dark),
                    points: points
                )
            )
        }

        if spec.showsAxes {
            elapsed += clock.measure {
                frame.xTicks = xScale.ticks(
                    target: spec.tickTarget,
                    axisLength: plot.width,
                    orientation: .horizontal,
                    measuring: measuring
                ).map { PlottedTick(position: xScale.map($0.value).normalised, label: $0.label) }

                frame.yTicks = yScale.ticks(
                    target: spec.tickTarget,
                    axisLength: plot.height,
                    orientation: .vertical,
                    measuring: measuring
                ).map { PlottedTick(position: yScale.map($0.value).normalised, label: $0.label) }
            }
        }

        frame.chrome = ChromeLayout.build(
            plot: plot, xTicks: frame.xTicks, yTicks: frame.yTicks, chrome: chrome, scale: scale
        )

        frame.prepareNs = elapsed.nanoseconds
        return frame
    }
}
