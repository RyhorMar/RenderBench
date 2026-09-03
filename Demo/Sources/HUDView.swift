import BenchRuntime
import SwiftUI

/// Reads numbers, computes none.
///
/// The overlay and the benchmark runner take their percentiles from the same sink, so the figure
/// on screen and the figure in a results file cannot disagree about what p95 means.
struct HUDView: View {
    let scene: ChartScene

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
            if let raster = scene.rasterStatistics {
                row("draw p50", milliseconds(raster.p50Ns))
                row("draw p95", milliseconds(raster.p95Ns))
            }
            row("points", "\(scene.frame.pointsDrawn)")
            row("dropped", "\(scene.droppedFrames)")
            // A refused series is shown, not absorbed. A chart quietly missing a curve is the one
            // failure mode a reader cannot detect from the picture.
            if scene.frame.failures.isEmpty == false {
                row("refused", "\(scene.frame.failures.count)")
                    .foregroundStyle(.red)
            }
        }
        .font(.system(size: 10, weight: .medium, design: .monospaced))
        .padding(6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
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
