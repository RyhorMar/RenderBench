import BenchDownsampling
import CanvasBackend
import SwiftUI

struct ContentView: View {
    @State private var scene = ChartScene()
    // Read inside the view that owns the renderer, not at App level: at App level the value is
    // aggregated across scenes and reports active while this one is not.
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 12) {
            header

            ChartPane(scene: scene)

            controls
        }
        .padding(12)
        .onAppear { scene.start() }
        .onDisappear { scene.stop() }
        .onChange(of: scene.scenario) { _, _ in scene.rebuild() }
        .onChange(of: colorScheme, initial: true) { _, scheme in scene.isDark = scheme == .dark }
        .onChange(of: scenePhase) { _, phase in
            // A render loop left running behind a backgrounded app keeps a CPU busy for pixels
            // nobody can see, and on a real device it shows up as battery rather than as a bug.
            if phase == .active { scene.start() } else { scene.stop() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("RenderBench")
                .font(.headline)
            Text("Canvas backend · \(scene.windowSeconds, specifier: "%.0f") s window")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var controls: some View {
        VStack(spacing: 10) {
            Picker("Signal", selection: $scene.scenario) {
                Text(Scenario.eightSeries.rawValue).tag(Scenario.eightSeries)
                Text(Scenario.carrier.rawValue).tag(Scenario.carrier)
            }
            .pickerStyle(.segmented)

            Picker("Downsampling", selection: $scene.policy) {
                Text("MinMax").tag(DownsamplePolicy.minMax)
                Text("LTTB").tag(DownsamplePolicy.lttb)
                Text("None").tag(DownsamplePolicy.none)
            }
            .pickerStyle(.segmented)

            // Fixed height, not intrinsic. The text is three lines for one combination and two for
            // another, and letting it size itself moves every control above it by several points
            // whenever the selection changes — under the reader's finger, mid-tap.
            Text(explanation)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 46, maxHeight: 46, alignment: .topLeading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var explanation: String {
        switch (scene.scenario, scene.policy) {
        case (.carrier, .lttb):
            "One column spans ten carrier periods. LTTB picks a representative sample per bucket, so the envelope collapses and a slow ripple appears that the signal does not contain."
        case (.carrier, .minMax):
            "MinMax reports the extremes of each column, so the full ±1 envelope survives even though the carrier is far finer than a pixel."
        case (.carrier, .none):
            "Every sample submitted: 5 000 per second against 400 points of axis. Faithful, and the cost of that shows in the frame time."
        default:
            "Eight phase-shifted reaction curves at 100 Hz. The well-behaved case — all three policies agree here, which is why the carrier signal is the one worth looking at."
        }
    }
}

/// The chart and its overlay, kept in a view of their own.
///
/// This is a boundary, not decoration. The frame geometry changes sixty times a second, so a body
/// that reads it is re-evaluated sixty times a second and takes everything else declared alongside
/// it along. Keeping the controls out of that body means the pickers are built once instead of
/// once per frame.
private struct ChartPane: View {
    let scene: ChartScene

    var body: some View {
        CanvasChartView(frame: scene.frame)
            .background(Color(.secondarySystemGroupedBackground))
            .overlay(alignment: .topTrailing) { HUDView(scene: scene).padding(8) }
            .onGeometryChange(for: CGSize.self) { $0.size } action: { scene.chartSize = $0 }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
    }
}
