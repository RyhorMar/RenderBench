import BenchRuntime
import Foundation
import simd

/// Points and segment indices for one draw, in device pixels with the origin at the top left.
///
/// Two buffers rather than one array of segments: a segment array would store every interior point
/// twice, and the doubling is paid on the CPU every frame in the one place this backend is trying
/// not to spend. The index list is what carries the breaks — a gap in the data is a segment that
/// is simply not indexed, which costs nothing at draw time.
public struct MetalLineGeometry: Sendable, Equatable {
    /// Polyline vertices, in device pixels.
    public var points: [SIMD2<Float>]
    /// Index of the first point of each drawn segment. `points[i]` to `points[i + 1]`.
    public var segmentStarts: [UInt32]

    public init(points: [SIMD2<Float>] = [], segmentStarts: [UInt32] = []) {
        self.points = points
        self.segmentStarts = segmentStarts
    }

    public var isEmpty: Bool { segmentStarts.isEmpty }
}

/// Turns a prepared frame's normalised points into pixel-space geometry.
public enum MetalGeometryBuilder {
    /// Projects one series into device pixels.
    ///
    /// - Parameters:
    ///   - scale: Device pixels per point. Positions are built in pixels because the vertex shader
    ///     offsets by half a stroke width along the segment normal, and that offset is only a
    ///     constant width if it is applied in the space the rasteriser measures.
    /// - Complexity: O(*n*), one pass, two appends per point at most.
    public static func build(
        series: PreparedSeries,
        plot: PlotRect,
        scale: Double
    ) -> MetalLineGeometry {
        var geometry = MetalLineGeometry()
        geometry.points.reserveCapacity(series.points.count)
        guard !series.points.isEmpty else { return geometry }

        // A break is not a point: emitting one and skipping its segments would leave the vertex
        // buffer holding coordinates no draw refers to, and any later change to the indexing
        // would start drawing them. Runs are kept contiguous instead.
        var runStart = 0
        for point in series.points {
            if point.isBreak {
                appendSegments(from: runStart, count: geometry.points.count - runStart, into: &geometry)
                runStart = geometry.points.count
                continue
            }
            let x = (plot.minX + point.x * plot.width) * scale
            let y = (plot.maxY - point.y * plot.height) * scale
            geometry.points.append(SIMD2<Float>(Float(x), Float(y)))
        }
        appendSegments(from: runStart, count: geometry.points.count - runStart, into: &geometry)
        return geometry
    }

    /// Straight lines given as pixel-space endpoint pairs — the grid and the axes.
    public static func build(strokes: [(SIMD2<Float>, SIMD2<Float>)]) -> MetalLineGeometry {
        var geometry = MetalLineGeometry()
        geometry.points.reserveCapacity(strokes.count * 2)
        geometry.segmentStarts.reserveCapacity(strokes.count)
        for stroke in strokes {
            geometry.segmentStarts.append(UInt32(geometry.points.count))
            geometry.points.append(stroke.0)
            geometry.points.append(stroke.1)
        }
        return geometry
    }

    private static func appendSegments(from start: Int, count: Int, into geometry: inout MetalLineGeometry) {
        guard count >= 2 else { return }
        geometry.segmentStarts.reserveCapacity(geometry.segmentStarts.count + count - 1)
        for index in start..<(start + count - 1) {
            geometry.segmentStarts.append(UInt32(index))
        }
    }
}
