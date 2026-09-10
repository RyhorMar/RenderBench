/// Every destination `RootView`'s navigation stack can push.
///
/// `Hashable` so it can be a `NavigationStack` path element; `Codable` so that path is restorable
/// (state restoration, deep links) without a second representation to keep in sync with this one.
enum Route: Hashable, Codable {
    /// One method's own screen, named by its catalogue identifier.
    case method(String)
    /// The multi-backend comparison screen.
    case compare
    /// The screen that takes a measurement.
    case measure

    /// The catalogue id this route names, or `nil` for the routes that own no registered scene. `RootView` diffs `path` through this to know which scene left the stack.
    var methodID: String? {
        if case .method(let id) = self { return id }
        return nil
    }
}
