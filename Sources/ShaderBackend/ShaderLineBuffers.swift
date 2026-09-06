import BenchRuntime
import Foundation
import SwiftUI

/// Packs one series' geometry into the `Data` buffers `Shader.Argument.data` hands the `chart_line`
/// fragment shader: plot-space `Float32` pairs, tightly packed, one buffer per contiguous run.
///
/// **Design decision this card makes, the brief leaves open:** a `[[stitchable]]` shader takes a
/// fixed argument list — it cannot accept "however many points this series happens to have" as a
/// variable-length list of buffers, and a flat single-buffer-per-series scheme would need a marker
/// value inside the buffer for the shader to notice a break and stop connecting segments across it,
/// scanned on every pixel of every segment in the series. Packing each contiguous run into its own
/// buffer and issuing one shader invocation per run instead turns a break into "one fewer buffer" —
/// nothing the shader has to parse for — at the cost of one more `colorEffect` composite per run,
/// paid by SwiftUI's compositor rather than by this type.
public enum ShaderLineBuffers {
    /// Bytes one packed point costs: two `Float32` components. `ChartLine.metal` recovers a
    /// buffer's point count as `byteCount / pointStride`; this constant is the one fact both sides
    /// of that division depend on, rather than each independently assuming 8.
    public static let pointStride = MemoryLayout<Float32>.size * 2

    /// Packs already-projected plot-space points into `x0,y0,x1,y1,…` `Float32` pairs, in the
    /// host's native byte order — the layout `device const float2 *` reads directly, with no
    /// per-element conversion on the GPU side.
    ///
    /// - Complexity: O(*n*) in `points`.
    public static func pack(_ points: [CGPoint]) -> Data {
        var data = Data(capacity: points.count * pointStride)
        for point in points {
            var x = Float32(point.x)
            var y = Float32(point.y)
            withUnsafeBytes(of: &x) { data.append(contentsOf: $0) }
            withUnsafeBytes(of: &y) { data.append(contentsOf: $0) }
        }
        return data
    }

    /// Splits one series into its contiguous runs — projecting each point into plot-space as it
    /// goes — and packs every run into its own buffer.
    ///
    /// A break ends the run before it without contributing a point of its own, the same treatment
    /// `MetalGeometryBuilder.build(series:plot:scale:)` gives one: a break carries no position, so
    /// keeping a placeholder for it would put a mark where the series has no measurement. A run of
    /// fewer than two points has no segment for the shader to draw and is dropped rather than
    /// packed into an invocation that could only ever report zero coverage — the same threshold
    /// `MetalGeometryBuilder.appendSegments` applies to its own index buffer.
    ///
    /// - Complexity: O(*n*) in `series.points`.
    public static func runs(for series: PreparedSeries, plot: PlotRect) -> [Data] {
        var buffers: [Data] = []
        var current: [CGPoint] = []
        current.reserveCapacity(series.points.count)

        func flush() {
            if current.count >= 2 { buffers.append(pack(current)) }
            current.removeAll(keepingCapacity: true)
        }

        for point in series.points {
            guard !point.isBreak else {
                flush()
                continue
            }
            current.append(CGPoint(
                x: plot.minX + point.x * plot.width,
                y: plot.maxY - point.y * plot.height
            ))
        }
        flush()
        return buffers
    }
}
