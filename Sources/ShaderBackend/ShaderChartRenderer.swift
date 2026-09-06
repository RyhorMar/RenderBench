import BenchRuntime
import Foundation
import SwiftUI

/// Turns a prepared frame into the buffers `ShaderChartView` hands to one `chart_line` invocation
/// per run.
///
/// Windowing, reduction and projection are not done here — they are `FramePreparation`'s, shared by
/// every backend. What is left is this method's own contribution: splitting each series into the
/// runs a break divides it into, and packing each run the way `ShaderLineBuffers` describes.
public enum ShaderChartRenderer {
    /// Builds one frame.
    ///
    /// - Complexity: O(*n*) in the points `prepared` carries.
    public static func encode(_ prepared: PreparedFrame) -> ShaderFrame {
        var frame = ShaderFrame()
        frame.plotRect = CGRect(
            x: prepared.plotRect.x,
            y: prepared.plotRect.y,
            width: prepared.plotRect.width,
            height: prepared.plotRect.height
        )
        frame.lineWidth = prepared.lineWidth
        frame.chrome = prepared.chrome
        frame.failures = prepared.failures
        frame.pointsSubmitted = prepared.pointsSubmitted

        guard prepared.plotRect.isDrawable else { return frame }

        let clock = ContinuousClock()
        var drawn = 0
        let elapsed = clock.measure {
            for series in prepared.series {
                let runs = ShaderLineBuffers.runs(for: series, plot: prepared.plotRect)
                for point in series.points where !point.isBreak { drawn += 1 }
                frame.series.append(ShaderSeriesBuffers(index: series.index, colour: series.colour, runs: runs))
            }
        }
        frame.pointsDrawn = drawn
        frame.encodeNs = elapsed.nanoseconds
        return frame
    }
}
