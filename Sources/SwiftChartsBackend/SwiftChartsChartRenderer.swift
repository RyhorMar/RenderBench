import BenchRuntime
import Foundation

/// Turns a prepared frame into the marks `SwiftChartsChartView` hands to `Chart`.
///
/// Windowing, reduction and projection are not done here — they are `FramePreparation`'s, shared
/// by every backend. What is left is this method's own contribution: splitting each series at its
/// breaks and keying the pieces so `Chart` draws one line per run instead of one line per series.
public enum SwiftChartsChartRenderer {
    /// Builds one frame.
    ///
    /// - Complexity: O(*n*) in the points `prepared` carries.
    public static func encode(_ prepared: PreparedFrame) -> SwiftChartsFrame {
        var frame = SwiftChartsFrame()
        frame.plotRect = prepared.plotRect
        frame.chrome = prepared.chrome
        frame.lineWidth = prepared.lineWidth
        frame.failures = prepared.failures
        frame.pointsSubmitted = prepared.pointsSubmitted
        guard prepared.plotRect.isDrawable else { return frame }

        let clock = ContinuousClock()
        var marks: [PlottedMark] = []
        marks.reserveCapacity(prepared.pointsSubmitted)
        let elapsed = clock.measure {
            for series in prepared.series {
                var runIndex = 0
                var runHasPoints = false
                for point in series.points {
                    guard !point.isBreak else {
                        if runHasPoints { runIndex += 1 }
                        runHasPoints = false
                        continue
                    }
                    marks.append(PlottedMark(
                        id: marks.count,
                        seriesKey: "\(series.index)-\(runIndex)",
                        colour: series.colour,
                        x: point.x,
                        y: point.y
                    ))
                    runHasPoints = true
                }
            }
        }
        frame.marks = marks
        frame.pointsDrawn = marks.count
        frame.encodeNs = elapsed.nanoseconds
        return frame
    }
}
