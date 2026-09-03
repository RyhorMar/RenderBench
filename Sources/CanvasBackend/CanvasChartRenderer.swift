import BenchCore
import BenchDownsampling
import BenchRuntime
import BenchScales
import SwiftUI

/// Turns provider data into the geometry a `Canvas` strokes.
public enum CanvasChartRenderer {
    /// Space reserved for axis labels, in points.
    static let leftInset: CGFloat = 52
    static let bottomInset: CGFloat = 22
    static let topInset: CGFloat = 10
    static let rightInset: CGFloat = 12

    /// Builds one frame.
    ///
    /// - Parameters:
    ///   - provider: Source of samples.
    ///   - spec: Which series, which downsampling policy, how wide the stroke.
    ///   - window: Carrier range on screen.
    ///   - yDomain: Value range on screen.
    ///   - size: Size of the whole chart, labels included.
    ///   - dark: Selects the palette variant.
    ///   - scratch: Reused downsampling buffer. Passing one in keeps a per-frame allocation off
    ///     the hot path; it is cleared on entry.
    /// - Complexity: O(*n*) in the samples inside the window.
    public static func buildFrame(
        provider: some ChartDataProvider,
        spec: LineChartSpec,
        window: ClosedRange<Carrier>,
        yDomain: ClosedRange<Double>,
        size: CGSize,
        dark: Bool,
        scratch: inout [Sample]
    ) -> CanvasFrame {
        var frame = CanvasFrame()
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

            var reduced: [Sample] = []
            prepare += clock.measure {
                provider.withSeries(seriesIndex, in: window) { slice in
                    try? downsample(
                        slice,
                        to: target,
                        policy: spec.policy,
                        xScale: xScale,
                        yScale: yScale,
                        into: &scratch
                    )
                }
                reduced = scratch
            }

            var path = Path()
            var drawn = 0
            encode += clock.measure {
                var penIsDown = false
                for sample in reduced {
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

            frame.pointsSubmitted += reduced.count
            frame.pointsDrawn += drawn
            frame.strokes.append(
                (colour: Palette.colour(forSeries: seriesIndex, dark: dark), path: path)
            )
        }

        if spec.showsAxes {
            let measurer = ApproximateTextWidth()
            encode += clock.measure {
                frame.xTicks = xScale.ticks(
                    target: spec.tickTarget,
                    axisLength: Double(plot.width),
                    measuring: measurer
                )
                frame.yTicks = yScale.ticks(
                    target: spec.tickTarget,
                    axisLength: Double(plot.height),
                    measuring: measurer
                )
            }
        }

        frame.prepareNs = prepare.nanoseconds
        frame.encodeNs = encode.nanoseconds
        return frame
    }
}

/// Width estimate for tick labels.
///
/// Deliberately arithmetic rather than a real text measurement: laying out a `Text` per candidate
/// label costs more than the tick selection it informs, and the digits of a monospaced-digit font
/// are uniform enough that a per-character constant is within a point of the truth. The protocol
/// exists so a caller who needs exactness can supply it.
struct ApproximateTextWidth: TextMeasuring {
    var pointsPerCharacter: Double = 7.5
    func width(of text: String) -> Double { Double(text.count) * pointsPerCharacter }
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
