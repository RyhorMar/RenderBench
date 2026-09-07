import SwiftUI

/// Root of the app: a list of every method plus the live comparison screen, one
/// `NavigationStack` deep for method screens.
struct RootView: View {
    @State private var path: [Route] = []
    @State private var registry = SceneRegistry()

    var body: some View {
        NavigationStack(path: $path) {
            List {
                ForEach(Catalogue.renderers) { entry in
                    NavigationLink(value: Route.method(entry.id)) {
                        Text(entry.descriptor.displayName)
                    }
                }
                NavigationLink("Compare", value: Route.compare)
            }
            .navigationTitle("RenderBench")
            // Attached to the List's content, not inside the ForEach that builds its rows: a
            // destination registered inside a lazy container is only wired up once that row has
            // been materialised, which silently breaks a deep link to a row never scrolled into
            // view.
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .method(let id):
                    MethodScreen(rendererID: id, registry: registry)
                case .compare:
                    CompareScreen()
                }
            }
        }
        .onChange(of: path) { oldPath, newPath in
            // The registry, not `MethodScreen.onDisappear`, is what tears a scene down: iOS may
            // keep a popped screen's view alive briefly, and `onDisappear` also fires when a sheet
            // merely covers a screen still on the path. A route id present before this change and
            // absent after it is the one signal that means "actually gone".
            let before = Set(oldPath.compactMap(\.methodID))
            let after = Set(newPath.compactMap(\.methodID))
            for id in before.subtracting(after) { registry.teardown(id) }
        }
    }
}
