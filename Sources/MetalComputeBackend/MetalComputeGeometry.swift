import BenchCore
import BenchRuntime
import Foundation

/// Points and segment indices for one draw, in device pixels with the origin at the top left.
///
/// Duplicated from `Sources/MetalBackend/MetalLineGeometry.swift`'s `MetalLineGeometry`: this
/// package's backends never depend on one another — the earlier decision to move
/// `ApproximateTextWidth` out of `CanvasBackend` rather than let a second backend reach for it set
/// that precedent — so the handful of lines an instanced-quad line pass needs are kept here too,
/// under this backend's own name, rather than imported.
struct MetalComputeLineGeometry: Sendable, Equatable {
    var points: [SIMD2<Float>] = []
    var segmentStarts: [UInt32] = []
    var isEmpty: Bool { segmentStarts.isEmpty }
}

/// Turns already-reduced, normalised runs into pixel-space geometry, and turns chrome strokes into
/// the same.
enum MetalComputeGeometryBuilder {
    /// Projects reduced runs into device pixels.
    ///
    /// - Parameters:
    ///   - runs: Points already reduced by ``MetalComputeReducer``, each run still in carrier
    ///     order and normalised `0...1`. A run of one point contributes a vertex but no segment,
    ///     exactly like every other backend's treatment of a single-point stretch.
    ///   - scale: Device pixels per point — positions are built in pixels because the vertex
    ///     shader offsets along the segment normal by a constant width only in the space the
    ///     rasteriser measures.
    static func build(runs: [NormalisedRun], plot: PlotRect, scale: Double) -> MetalComputeLineGeometry {
        var geometry = MetalComputeLineGeometry()
        for run in runs {
            let start = geometry.points.count
            for point in run.points {
                let x = (plot.minX + Double(point.x) * plot.width) * scale
                let y = (plot.maxY - Double(point.y) * plot.height) * scale
                geometry.points.append(SIMD2<Float>(Float(x), Float(y)))
            }
            appendSegments(from: start, count: run.points.count, into: &geometry)
        }
        return geometry
    }

    /// Straight lines given as pixel-space endpoint pairs — the grid and the axes.
    static func build(strokes: [(SIMD2<Float>, SIMD2<Float>)]) -> MetalComputeLineGeometry {
        var geometry = MetalComputeLineGeometry()
        geometry.points.reserveCapacity(strokes.count * 2)
        geometry.segmentStarts.reserveCapacity(strokes.count)
        for stroke in strokes {
            geometry.segmentStarts.append(UInt32(geometry.points.count))
            geometry.points.append(stroke.0)
            geometry.points.append(stroke.1)
        }
        return geometry
    }

    private static func appendSegments(from start: Int, count: Int, into geometry: inout MetalComputeLineGeometry) {
        guard count >= 2 else { return }
        geometry.segmentStarts.reserveCapacity(geometry.segmentStarts.count + count - 1)
        for index in start..<(start + count - 1) {
            geometry.segmentStarts.append(UInt32(index))
        }
    }
}

/// One draw's worth of segments: the colour and width they share, and where they sit.
struct MetalComputeDrawBatch: Sendable, Equatable {
    let colour: PaletteColor
    let halfWidth: Float
    let extend: Float
    let segmentRange: Range<Int>
}

/// Everything one frame draws, flattened into two buffers and a list of draws — the reduced
/// series' geometry plus the chart's chrome.
///
/// Built without touching an `MTLDevice`, so ``build(_:reducedRuns:scale:)`` is testable on any
/// host, including one where `MTLCreateSystemDefaultDevice()` returns `nil`; only drawing it
/// needs a device.
struct MetalComputeChartGeometry: Sendable, Equatable {
    var points: [SIMD2<Float>] = []
    var segmentStarts: [UInt32] = []
    var batches: [MetalComputeDrawBatch] = []

    var isEmpty: Bool { batches.isEmpty }
    var vertexCount: Int { segmentStarts.count * 6 }

    /// Assembles chrome and the already-GPU-reduced series into one upload.
    ///
    /// - Parameters:
    ///   - reducedRuns: One entry per `frame.series`, in the same order, holding what
    ///     ``MetalComputeReducer/reduce(runsPerSeries:plotWidth:)`` returned for it.
    ///   - scale: Device pixels per point.
    static func build(
        _ frame: PreparedFrame,
        reducedRuns: [[NormalisedRun]],
        scale: Double
    ) -> MetalComputeChartGeometry {
        var geometry = MetalComputeChartGeometry()
        let plot = frame.plotRect
        guard plot.isDrawable else { return geometry }

        // Chrome first, exactly as `MetalChartGeometry.build` orders it: with blending off and no
        // depth test, later draws overwrite earlier ones, and the series must sit on top of the
        // grid the same way they do in every other backend.
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
                MetalComputeGeometryBuilder.build(strokes: strokes),
                colour: style.colour,
                width: style.width * scale
            )
        }

        for (seriesIndex, series) in frame.series.enumerated() {
            let runs = seriesIndex < reducedRuns.count ? reducedRuns[seriesIndex] : []
            geometry.append(
                MetalComputeGeometryBuilder.build(runs: runs, plot: plot, scale: scale),
                colour: series.colour,
                width: frame.lineWidth * scale
            )
        }
        return geometry
    }

    private mutating func append(_ piece: MetalComputeLineGeometry, colour: PaletteColor, width: Double) {
        guard !piece.isEmpty else { return }
        let pointOffset = UInt32(points.count)
        let segmentStart = segmentStarts.count
        points.append(contentsOf: piece.points)
        segmentStarts.append(contentsOf: piece.segmentStarts.map { $0 + pointOffset })
        let halfWidth = Float(width / 2)
        batches.append(
            MetalComputeDrawBatch(
                colour: colour,
                halfWidth: halfWidth,
                // Segments are extended by half a stroke width at both ends, the same join
                // treatment and the same documented difference from a bevel join as
                // `MetalBackend`'s own geometry, described in
                // Docs/methods/gpu-lines.md
                // This backend is judged by the same equivalence check, so guessing whether the
                // difference is visible here would defeat the point of running it.
                extend: halfWidth,
                segmentRange: segmentStart..<segmentStarts.count
            )
        )
    }
}
