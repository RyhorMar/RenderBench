import BenchCore
import BenchDownsampling
import BenchRuntime
import BenchScales
import SwiftUI

/// Turns a prepared frame into the geometry a `Canvas` strokes.
///
/// Windowing, reduction and projection are not done here — they are `FramePreparation`'s, shared by
/// every backend. What is left is this method's own contribution: building `Path` values. Timing
/// only that is what makes a comparison between backends a statement about the backends.
public enum CanvasChartRenderer {
    /// Builds one frame.
    ///
    /// - Parameters:
    ///   - scratch: Reused reduction buffer, passed through to the preparation.
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
        let prepared = FramePreparation.prepare(
            provider: provider,
            spec: spec,
            window: window,
            yDomain: yDomain,
            size: (width: Double(size.width), height: Double(size.height)),
            chrome: .forScheme(dark: dark),
            scale: 1,
            dark: dark,
            measuring: measuring,
            scratch: &scratch
        )
        return encode(prepared)
    }

    /// Turns a prepared frame into stroked paths.
    ///
    /// Separate and public so a benchmark can time encoding alone, and so a test can hand in a
    /// frame it built by hand rather than going through a provider.
    public static func encode(_ prepared: PreparedFrame) -> CanvasFrame {
        var frame = CanvasFrame()
        let plot = CGRect(
            x: prepared.plotRect.x,
            y: prepared.plotRect.y,
            width: prepared.plotRect.width,
            height: prepared.plotRect.height
        )
        frame.plotRect = plot
        frame.lineWidth = prepared.lineWidth
        frame.failures = prepared.failures
        frame.xTicks = prepared.xTicks
        frame.yTicks = prepared.yTicks
        frame.pointsSubmitted = prepared.pointsSubmitted
        frame.prepareNs = prepared.prepareNs
        guard plot.width > 1, plot.height > 1 else { return frame }

        let clock = ContinuousClock()
        var drawn = 0
        let elapsed = clock.measure {
            for series in prepared.series {
                var path = Path()
                var penIsDown = false
                for point in series.points {
                    guard !point.isBreak else {
                        penIsDown = false
                        continue
                    }
                    let location = CGPoint(
                        x: plot.minX + CGFloat(point.x) * plot.width,
                        y: plot.maxY - CGFloat(point.y) * plot.height
                    )
                    if penIsDown {
                        path.addLine(to: location)
                    } else {
                        path.move(to: location)
                        penIsDown = true
                    }
                    drawn += 1
                }
                frame.strokes.append((colour: series.colour, path: path))
            }
        }
        frame.pointsDrawn = drawn
        frame.encodeNs = elapsed.nanoseconds
        return frame
    }
}

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
