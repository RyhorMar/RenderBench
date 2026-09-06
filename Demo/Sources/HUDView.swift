import BenchHost
import BenchRuntime
import SwiftUI

/// Reads numbers, computes none.
///
/// The overlay and the benchmark runner take their percentiles from the same sink, so the figure
/// on screen and the figure in a results file cannot disagree about what p95 means.
struct HUDView: View {
    let scene: ChartScene

    /// Identity and reporting capabilities of the backend currently drawing. Read fresh every
    /// `body`, so switching backends changes which rows can show a number without this view
    /// needing to know that happened.
    private var descriptor: RendererDescriptor { type(of: scene.renderer).descriptor }

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            row("fps", String(format: "%.0f", scene.observedHz))
            // Two columns, not one. "prep" is preparation plus geometry building; "draw" is the
            // rasterisation the backend could time. Adding them into a single figure and calling
            // it the frame cost is what this overlay did until the draw pass was measured at all.
            if let statistics = scene.statistics {
                row("prep p50", milliseconds(statistics.p50Ns))
                row("prep p95", milliseconds(statistics.p95Ns))
            }
            row("draw p50", rasterValue(\.p50Ns))
            row("draw p95", rasterValue(\.p95Ns))
            row("gpu p50", gpuValue(\.p50Ns))
            row("gpu p95", gpuValue(\.p95Ns))
            row("points", scene.pointsDrawn.map { "\($0)" } ?? "—")
            row("dropped", "\(scene.droppedFrames)")
            // A refused series is shown, not absorbed. A chart quietly missing a curve is the one
            // failure mode a reader cannot detect from the picture.
            if scene.failures.isEmpty == false {
                row("refused", "\(scene.failures.count)")
                    .foregroundStyle(.red)
            }
        }
        .font(.system(size: 10, weight: .medium, design: .monospaced))
        .padding(6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
    }

    /// A dash where the descriptor says this backend cannot time its own draw pass, never a zero:
    /// a zero here would read as "the fastest backend measured" rather than "not measured at all".
    private func rasterValue(_ path: KeyPath<FrameStatistics, UInt64>) -> String {
        guard descriptor.reportsRasterTime, let raster = scene.rasterStatistics else { return "—" }
        return milliseconds(raster[keyPath: path])
    }

    /// See ``rasterValue(_:)``; same reasoning, the GPU-timestamp column.
    private func gpuValue(_ path: KeyPath<FrameStatistics, UInt64>) -> String {
        guard descriptor.reportsGPUTime, let gpu = scene.gpuStatistics else { return "—" }
        return milliseconds(gpu[keyPath: path])
    }

    private func row(_ name: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(name).foregroundStyle(.secondary)
            Text(value).monospacedDigit()
        }
    }

    private func milliseconds(_ nanoseconds: UInt64) -> String {
        String(format: "%.2f ms", Double(nanoseconds) / 1_000_000)
    }
}
