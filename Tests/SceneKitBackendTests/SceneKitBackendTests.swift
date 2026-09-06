import Testing
@testable import SceneKitBackend

/// The identifier appears in every stored benchmark result. Changing it orphans past runs.
@Test
func identifierIsPinned() {
    #expect(SceneKitBackend.identifier == "scenekit")
}
