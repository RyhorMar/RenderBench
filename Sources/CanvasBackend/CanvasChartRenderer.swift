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
        frame.chrome = prepared.chrome
        frame.failures = prepared.failures
        frame.xTicks = prepared.xTicks
        frame.yTicks = prepared.yTicks
        frame.pointsSubmitted = prepared.pointsSubmitted
        frame.prepareNs = prepared.prepareNs

        let isDrawable = plot.width > 1 && plot.height > 1
        // One call for the background fill, always issued by `CanvasChartView.draw(in:size:)`;
        // the chrome's grouped strokes and one stroke per series follow only when there is a plot
        // to draw into, mirroring the guard below.
        frame.drawCalls = 1 + (isDrawable ? chromeStrokeGroupCount(prepared.chrome.lines) + prepared.series.count : 0)
        guard isDrawable else { return frame }

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

    /// Counts the grouped strokes `CanvasChartView.strokeChrome` will issue for chrome lines: one
    /// per run of consecutive lines sharing a colour and width, the same grouping the view itself
    /// performs so that two touching lines do not blend their antialiased edges as separate draws.
    private static func chromeStrokeGroupCount(_ lines: [ChromeLine]) -> Int {
        var count = 0
        var index = 0
        while index < lines.count {
            let style = lines[index]
            count += 1
            while index < lines.count, lines[index].colour == style.colour, lines[index].width == style.width {
                index += 1
            }
        }
        return count
    }
}
