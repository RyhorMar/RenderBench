import BenchDownsampling
import BenchHost
import SwiftUI

/// The one screen where a single scene switches live between every backend, kept distinct from
/// ``MethodScreen``: there each pushed screen owns one renderer for its lifetime, here one scene
/// owns a sequence of renderers via ``ChartScene/switchRenderer(to:)``.
struct CompareScreen: View {
    @State private var scene = ChartScene()
    // Read inside the view that owns the renderer, not at App level: at App level the value is
    // aggregated across scenes and reports active while this one is not.
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    /// Name of the last file written, shown on the button so the user knows what to look for in
    /// Files. Deliberately not a success alert: an export is not an event worth interrupting for.
    @State private var exportedFile: String?

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
        HStack(alignment: .firstTextBaseline) {
            titles
            Spacer()
            exportButton
        }
    }

    private var exportButton: some View {
        Button {
            exportedFile = ResultExport.write(from: scene)
        } label: {
            Label(exportedFile ?? "Export", systemImage: "square.and.arrow.up")
                .font(.caption)
                .labelStyle(.titleAndIcon)
        }
        .buttonStyle(.bordered)
        .disabled(scene.statistics == nil || scene.pointsDrawn == nil || scene.drawCalls == nil)
    }

    private var titles: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("RenderBench")
                .font(.headline)
            Text("\(type(of: scene.renderer).descriptor.displayName) backend · \(scene.windowSeconds, specifier: "%.0f") s window")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var controls: some View {
        VStack(spacing: 10) {
            BackendChipRow(rows: Catalogue.rows, selection: backendSelection)

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

    /// `scene.renderer` has no `Binding` of its own — replacing it is `switchRenderer(to:)`, not
    /// assignment — so the picker binds to the identifier instead and resolves it back through
    /// the catalogue on write.
    private var backendSelection: Binding<String> {
        Binding(
            get: { scene.rendererID },
            set: { id in
                guard let entry = Catalogue.renderers.first(where: { $0.id == id }) else { return }
                scene.switchRenderer(to: entry)
            }
        )
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
/// once per frame. Not `private`: ``MethodScreen`` shares this boundary, since the same geometry
/// argument applies to a screen with one fixed backend as much as to one that switches between
/// them.
struct ChartPane: View {
    let scene: ChartScene

    var body: some View {
        // The clip and the border are on the frame, not on the chart. Reading the per-frame
        // geometry inside a body that also carries a rounded mask and a stroked overlay made the
        // compositor redo both at frame rate, and charged them to the same main-thread frame the
        // measurement is about.
        ChartSurface(scene: scene)
            .onGeometryChange(for: CGSize.self) { $0.size } action: { scene.chartSize = $0 }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
    }
}

/// The only view that reads the per-frame geometry, and therefore the only one re-evaluated at
/// frame rate.
private struct ChartSurface: View {
    let scene: ChartScene

    var body: some View {
        scene.renderer.surface
            .overlay(alignment: .topTrailing) { HUDView(scene: scene).padding(8) }
    }
}
