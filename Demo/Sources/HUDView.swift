import BenchDownsampling
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
            // The identifier names the value cell alone, not the row: a UI test reads this text
            // as a number and expects it to climb, which `row`'s shared label half never does.
            HStack(spacing: 6) {
                Text("frames").foregroundStyle(.secondary)
                Text("\(scene.framesDrawn)")
                    .monospacedDigit()
                    .accessibilityIdentifier("hud.frames")
            }
            row("fps", String(format: "%.0f", scene.observedHz))
            row("policy", policyLabel)
            // Two columns, not one. "prep" is preparation plus geometry building; "draw" is the
            // rasterisation the backend could time. Adding them into a single figure and calling
            // it the frame cost is what this overlay did until the draw pass was measured at all.
            if let statistics = scene.statistics {
                row("prep p50", HUDFormat.milliseconds(statistics.p50Ns))
                row("prep p95", HUDFormat.milliseconds(statistics.p95Ns))
            }
            row("draw p50", rasterValue(\.p50Ns))
            row("draw p95", rasterValue(\.p95Ns))
            row("gpu p50", gpuValue(\.p50Ns))
            row("gpu p95", gpuValue(\.p95Ns))
            row("points", HUDFormat.count(scene.pointsDrawn))
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

    /// Absent where the descriptor says this backend cannot time its own draw pass, never a zero:
    /// a zero here would read as "the fastest backend measured" rather than "not measured at all".
    private func rasterValue(_ path: KeyPath<FrameStatistics, UInt64>) -> String {
        let raster = descriptor.reportsRasterTime ? scene.rasterStatistics : nil
        return HUDFormat.milliseconds(raster?[keyPath: path])
    }

    /// See ``rasterValue(_:)``; same reasoning, the GPU-timestamp column.
    private func gpuValue(_ path: KeyPath<FrameStatistics, UInt64>) -> String {
        let gpu = descriptor.reportsGPUTime ? scene.gpuStatistics : nil
        return HUDFormat.milliseconds(gpu?[keyPath: path])
    }

    /// `scene.policy` names what the picker selected, not what actually reached the backend: for
    /// the one backend that reduces on the GPU, `ChartScene.advance(_:)` overrides it to `.none`
    /// before `FramePreparation.prepare` ever sees it, so showing `scene.policy` unchanged here
    /// would claim a CPU reduction this frame never ran.
    private var policyLabel: String {
        guard !descriptor.reducesOnGPU else { return "MinMax (GPU)" }
        switch scene.policy {
        case .minMax: return "MinMax"
        case .lttb: return "LTTB"
        case .none: return "None"
        }
    }

    private func row(_ name: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(name).foregroundStyle(.secondary)
            Text(value).monospacedDigit()
        }
    }
}

/// How a reading is written, and there is one answer for the whole overlay.
///
/// An absent value is the literal word `nil`, not a dash. A dash does not explain itself: a reader
/// cannot tell "this backend cannot report it" from "the row is a separator" from "somebody left a
/// placeholder". `nil` is the same word the code uses for the same thing, and it is the same
/// argument by which this project writes an absent counter as absent rather than as zero.
///
/// Zero is not absence and is never rewritten: a backend that honestly counted zero dropped frames
/// says `0`.
enum HUDFormat {
    static let absent = "nil"

    static func count(_ value: Int?) -> String {
        guard let value else { return absent }
        return "\(value)"
    }

    static func milliseconds(_ nanoseconds: UInt64?) -> String {
        guard let nanoseconds else { return absent }
        return String(format: "%.2f ms", Double(nanoseconds) / 1_000_000)
    }
}
