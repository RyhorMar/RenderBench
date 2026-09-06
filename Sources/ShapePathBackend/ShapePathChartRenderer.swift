import BenchRuntime
import Foundation
import SwiftUI

/// Turns a prepared frame into the geometry `ShapePathChartView` hands to one `PolylineShape` per
/// series.
///
/// Windowing, reduction and projection are not done here — they are `FramePreparation`'s, shared by
/// every backend. What is left is this method's own contribution: turning normalised points into
/// absolute plot-space coordinates and recording where each series breaks, so `PolylineShape`
/// never has to see a placeholder break point at all.
public enum ShapePathChartRenderer {
    /// Builds one frame.
    ///
    /// - Complexity: O(*n*) in the points `prepared` carries.
    public static func encode(_ prepared: PreparedFrame) -> ShapePathFrame {
        var frame = ShapePathFrame()
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
        frame.pointsSubmitted = prepared.pointsSubmitted

        let isDrawable = plot.width > 1 && plot.height > 1
        guard isDrawable else { return frame }

        let clock = ContinuousClock()
        var drawn = 0
        let elapsed = clock.measure {
            for series in prepared.series {
                var points: [CGPoint] = []
                points.reserveCapacity(series.points.count)
                var breaks: Set<Int> = []
                for point in series.points {
                    guard !point.isBreak else {
                        // A break with nothing before it yet needs no mark: `PolylineShape`
                        // already starts a fresh subpath at index 0.
                        if !points.isEmpty { breaks.insert(points.count) }
                        continue
                    }
                    points.append(CGPoint(
                        x: plot.minX + CGFloat(point.x) * plot.width,
                        y: plot.maxY - CGFloat(point.y) * plot.height
                    ))
                    drawn += 1
                }
                frame.series.append(
                    ShapePathSeries(index: series.index, colour: series.colour, points: points, breaks: breaks)
                )
            }
        }
        frame.pointsDrawn = drawn
        frame.encodeNs = elapsed.nanoseconds
        return frame
    }
}
