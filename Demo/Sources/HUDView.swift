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
            if let statistics = scene.statistics {
                row("p50", milliseconds(statistics.p50Ns))
                row("p95", milliseconds(statistics.p95Ns))
                row("p99", milliseconds(statistics.p99Ns))
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
