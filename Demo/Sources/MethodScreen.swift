import BenchDownsampling
import SwiftUI

/// One backend, pushed for the catalogue entry named `rendererID`. Its scene is created once, in
/// `init`, and lives for exactly as long as this screen is on the navigation path — see
/// ``SceneRegistry`` for how `RootView` guarantees the renderer beneath it is released even if the
/// view itself lingers past that point.
struct MethodScreen: View {
    let rendererID: String
    @State private var scene: ChartScene
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    private let registry: SceneRegistry

    /// - Parameters:
    ///   - rendererID: The catalogue entry this screen draws. Falls back to the catalogue's first
    ///     entry if the id no longer matches one — a stale deep link shows a chart rather than
    ///     failing to resolve one at all.
    ///   - registry: Where this screen's scene is recorded so `RootView` can tear it down when the
    ///     route naming `rendererID` leaves the path.
    init(rendererID: String, registry: SceneRegistry) {
        self.rendererID = rendererID
        self.registry = registry
        let entry = Catalogue.renderers.first(where: { $0.id == rendererID }) ?? Catalogue.renderers[0]
        _scene = State(initialValue: ChartScene(renderer: entry.make()))
    }

    var body: some View {
        VStack(spacing: 12) {
            Text(displayName)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                // On the enclosing `VStack` this identifier reached every descendant accessibility
                // element, `hud.frames` included, and replaced each one's own — confirmed by
                // dumping the accessibility tree under `NavigationUITests`. Scoped to the title
                // alone, it still names which screen is showing without touching the HUD's.
                .accessibilityIdentifier("screen.method.\(rendererID)")

            ChartPane(scene: scene)

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
        }
        .padding(12)
        .onAppear {
            registry.register(scene, for: rendererID)
            scene.start()
        }
        .onDisappear { scene.stop() }
        .onChange(of: scene.scenario) { _, _ in scene.rebuild() }
        .onChange(of: colorScheme, initial: true) { _, scheme in scene.isDark = scheme == .dark }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { scene.start() } else { scene.stop() }
        }
    }

    private var displayName: String {
        type(of: scene.renderer).descriptor.displayName
    }
}
