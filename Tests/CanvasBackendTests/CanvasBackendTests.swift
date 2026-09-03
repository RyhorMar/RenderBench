import Testing
@testable import CanvasBackend

/// The identifier appears in every stored benchmark result. Changing it orphans past runs.
@Test
func identifierIsPinned() {
    #expect(CanvasBackend.identifier == "canvas")
}
