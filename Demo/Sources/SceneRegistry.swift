import BenchHost

/// A weak reference to one screen's scene, wrapped because Swift will not let a dictionary value
/// be declared `weak` directly.
@MainActor
final class WeakChartSceneBox {
    weak var scene: ChartScene?
    init(_ scene: ChartScene) { self.scene = scene }
}

/// Tears down a method screen's GPU-owning scene the moment its route actually leaves the
/// navigation path — the one signal `View.onDisappear` cannot give, since that also fires when a
/// sheet is presented over a screen that is still on the stack.
///
/// A scene belongs to the screen that created it; this registry belongs to the app. iOS may keep a
/// popped screen's view hierarchy alive briefly, and per the platform's own documented behaviour
/// `deinit` can arrive late or never during a screen transition — so releasing a renderer cannot
/// wait on deallocation. `MethodScreen` registers here on appearance; `RootView` calls
/// ``teardown(_:)`` from its `path` observer when a `Route.method` id present before a change is
/// absent after it.
@MainActor
final class SceneRegistry {
    private var scenes: [String: WeakChartSceneBox] = [:]

    func register(_ scene: ChartScene, for rendererID: String) {
        scenes[rendererID] = WeakChartSceneBox(scene)
    }

    /// Stops and releases the scene for `rendererID` if it is still alive, then forgets the entry
    /// either way. A nil scene means the screen's view was already released before its route left
    /// the path — nothing left to tear down.
    func teardown(_ rendererID: String) {
        if let scene = scenes[rendererID]?.scene {
            scene.stop()
            scene.renderer.teardown()
        }
        scenes[rendererID] = nil
    }
}
