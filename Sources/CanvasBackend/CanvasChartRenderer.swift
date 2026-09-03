import BenchCore
import BenchDownsampling
import BenchRuntime
import BenchScales
import SwiftUI

/// Width estimate for tick labels.
///
/// Deliberately arithmetic rather than a real text layout: laying out a `Text` per candidate label
/// costs more than the tick selection it informs, and the digits of a monospaced-digit font are
/// uniform enough that a per-character constant is within a point of the truth.
///
/// Public and injectable, because the numbers it produces are the input to collision avoidance: a
/// caller who needs CoreText metrics, or a test that needs to pin a tick count, has to be able to
/// supply their own.
public struct ApproximateTextWidth: TextMeasuring {
    public var pointsPerCharacter: Double
    public var lineHeight: Double

    public init(pointsPerCharacter: Double = 7.5, lineHeight: Double = 11) {
        self.pointsPerCharacter = pointsPerCharacter
        self.lineHeight = lineHeight
    }

    public func width(of text: String) -> Double {
        Double(text.count) * pointsPerCharacter
    }
}

/// Turns provider data into the geometry a `Canvas` strokes.
public enum CanvasChartRenderer {
    /// Space reserved for axis labels, in points.
    public static let leftInset: CGFloat = 52
    public static let bottomInset: CGFloat = 22
    public static let topInset: CGFloat = 10
    public static let rightInset: CGFloat = 12

    /// Builds one frame.
    ///
    /// - Parameters:
    ///   - provider: Source of samples.
    ///   - spec: Which series, which downsampling policy, how wide the stroke.
    ///   - window: Carrier range on screen.
    ///   - yDomain: Value range on screen.
    ///   - size: Size of the whole chart, labels included.
    ///   - dark: Selects the palette variant.
    ///   - measuring: Supplies label metrics for tick collision avoidance.
    ///   - scratch: Reused downsampling buffer. Passing one in keeps a per-frame allocation off
    ///     the hot path; it is cleared on entry and read in place, never copied out.
    /// - Complexity: O(*n*) in the samples inside the window.
    public static func buildFrame(
        provider: some ChartDataProvider,
        spec: LineChartSpec,
        window: ClosedRange<Carrier>,
        yDomain: ClosedRange<Double>,
        size: CGSize,
        dark: Bool,
        measuring: some TextMeasuring = ApproximateTextWidth(),
        scratch: inout [Sample]
    ) -> CanvasFrame {
        var frame = CanvasFrame()
        frame.lineWidth = spec.lineWidth
        let plot = CGRect(
            x: leftInset,
            y: topInset,
            width: max(0, size.width - leftInset - rightInset),
            height: max(0, size.height - topInset - bottomInset)
        )
        frame.plotRect = plot
        guard plot.width > 1, plot.height > 1, window.upperBound > window.lowerBound else {
            return frame
        }

        let xScale = TimeScale(domain: window)
        let yScale = LinearScale(domain: yDomain)
        // One target point per horizontal point of the plot. Asking for more than the display can
        // resolve is work whose result no one can see.
        let target = max(2, Int(plot.width))

        let clock = ContinuousClock()
        var prepare = Duration.zero
        var encode = Duration.zero

        for seriesIndex in spec.series {
            guard seriesIndex < provider.seriesCount else { continue }

            var failure: ChartError?
            prepare += clock.measure {
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
                        // `downsample` declares `throws(ChartError)`; this arm exists only so the
                        // typed throw cannot be widened later without the compiler saying so.
                        failure = .emptyDomain
                    }
                }
            }

            // A refusal is reported, not absorbed. Appending an empty path here — which is what
            // discarding the error did — draws a chart with the series simply missing while
            // `pointsDrawn == pointsSubmitted` still reads clean.
            if let failure {
                frame.failures.append(SeriesFailure(seriesIndex: seriesIndex, error: failure))
                continue
            }

            var path = Path()
            var drawn = 0
            encode += clock.measure {
                var penIsDown = false
                for sample in scratch {
                    guard !sample.value.isNaN else {
                        penIsDown = false
                        continue
                    }
                    let x = plot.minX + CGFloat(xScale.map(sample.carrier).normalised) * plot.width
                    let y = plot.maxY - CGFloat(yScale.map(sample.value).normalised) * plot.height
                    let point = CGPoint(x: x, y: y)
                    if penIsDown {
                        path.addLine(to: point)
                    } else {
                        path.move(to: point)
                        penIsDown = true
                    }
                    drawn += 1
                }
            }

            frame.pointsSubmitted += scratch.count
            frame.pointsDrawn += drawn
            frame.strokes.append(
                (colour: Palette.colour(forSeries: seriesIndex, dark: dark), path: path)
            )
        }

        if spec.showsAxes {
            encode += clock.measure {
                // Projected through the same scales that placed the samples, so a label cannot
                // disagree with the curve it names.
                frame.xTicks = xScale.ticks(
                    target: spec.tickTarget,
                    axisLength: Double(plot.width),
                    orientation: .horizontal,
                    measuring: measuring
                ).map { PlottedTick(position: xScale.map($0.value).normalised, label: $0.label) }

                frame.yTicks = yScale.ticks(
                    target: spec.tickTarget,
                    axisLength: Double(plot.height),
                    orientation: .vertical,
                    measuring: measuring
                ).map { PlottedTick(position: yScale.map($0.value).normalised, label: $0.label) }
            }
        }

        frame.prepareNs = prepare.nanoseconds
        frame.encodeNs = encode.nanoseconds
        return frame
    }
}

extension Duration {
    /// This duration in whole nanoseconds.
    var nanoseconds: UInt64 {
        let parts = components
        let seconds = UInt64(max(0, parts.seconds))
        let fraction = UInt64(max(0, parts.attoseconds) / 1_000_000_000)
        return seconds &* 1_000_000_000 &+ fraction
    }
}
