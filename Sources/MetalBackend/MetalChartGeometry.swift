import BenchCore
import BenchRuntime
import Foundation
import simd

/// One draw's worth of segments: the colour and width they share, and where they sit.
public struct MetalDrawBatch: Sendable, Equatable {
    public let colour: PaletteColor
    public let halfWidth: Float
    /// How far each segment is stretched past its endpoints, in pixels.
    public let extend: Float
    /// Range within ``MetalChartGeometry/segmentStarts``, used as `baseInstance` and count.
    public let segmentRange: Range<Int>
}

/// Everything one frame draws, flattened into two buffers and a list of draws.
///
/// One upload per frame rather than one per series: the buffers are concatenated and each batch
/// names its own slice through `baseInstance`. A per-series upload would spend the frame doing
/// exactly the bookkeeping this backend exists to avoid, and would make the comparison against the
/// retained-mode backends a comparison of two upload strategies.
///
/// Built without touching a `MTLDevice`, so it can be tested on any host — including one where
/// `MTLCreateSystemDefaultDevice()` returns nil.
public struct MetalChartGeometry: Sendable, Equatable {
    public var points: [SIMD2<Float>] = []
    public var segmentStarts: [UInt32] = []
    public var batches: [MetalDrawBatch] = []
    var extendSegments = true

    public var isEmpty: Bool { batches.isEmpty }
    /// Vertices the GPU will actually process: six per segment.
    public var vertexCount: Int { segmentStarts.count * 6 }

    /// Assembles chrome and series into one upload.
    ///
    /// - Parameters:
    ///   - scale: Device pixels per point. Everything below is in pixels, because the shader
    ///     offsets along the segment normal and that is only a constant width in pixel space.
    /// - Complexity: O(*n*) in the frame's points.
    public static func build(
        _ frame: PreparedFrame,
        scale: Double,
        extendSegments: Bool = true
    ) -> MetalChartGeometry {
        var geometry = MetalChartGeometry()
        geometry.extendSegments = extendSegments
        let plot = frame.plotRect
        guard plot.isDrawable else { return geometry }

        // Chrome first: with blending off and no depth test, later draws overwrite earlier ones,
        // and the series must sit on top of the grid exactly as they do in the other backends.
        // `frame.chrome.lines` already sits pixel-snapped in points, so scale is the only thing
        // this backend still applies — applying `PixelSnap` again here would snap twice.
        var index = 0
        while index < frame.chrome.lines.count {
            let style = frame.chrome.lines[index]
            var strokes: [(SIMD2<Float>, SIMD2<Float>)] = []
            while index < frame.chrome.lines.count,
                  frame.chrome.lines[index].colour == style.colour,
                  frame.chrome.lines[index].width == style.width {
                let line = frame.chrome.lines[index]
                strokes.append((
                    SIMD2<Float>(Float(line.x0 * scale), Float(line.y0 * scale)),
                    SIMD2<Float>(Float(line.x1 * scale), Float(line.y1 * scale))
                ))
                index += 1
            }
            geometry.append(
                MetalGeometryBuilder.build(strokes: strokes),
                colour: style.colour,
                width: style.width * scale
            )
        }

        for series in frame.series {
            geometry.append(
                MetalGeometryBuilder.build(series: series, plot: plot, scale: scale),
                colour: series.colour,
                width: frame.lineWidth * scale
            )
        }
        return geometry
    }

    private mutating func append(_ piece: MetalLineGeometry, colour: PaletteColor, width: Double) {
        guard !piece.isEmpty else { return }
        let pointOffset = UInt32(points.count)
        let segmentStart = segmentStarts.count
        points.append(contentsOf: piece.points)
        segmentStarts.append(contentsOf: piece.segmentStarts.map { $0 + pointOffset })
        let halfWidth = Float(width / 2)
        batches.append(
            MetalDrawBatch(
                colour: colour,
                halfWidth: halfWidth,
                // Each segment is stretched by half a stroke width at both ends so that adjacent
                // segments overlap and leave no notch at a corner. It is a cheaper stand-in for
                // the bevel join the CoreGraphics backends use, and it is not the same shape: at
                // the two ends of a polyline it produces a square cap where they produce a round
                // one, and on a sharp turn it fills more than a bevel would. The equivalence check
                // is what says whether that difference is visible; guessing would defeat it.
                extend: extendSegments ? halfWidth : 0,
                segmentRange: segmentStart..<segmentStarts.count
            )
        )
    }
}
