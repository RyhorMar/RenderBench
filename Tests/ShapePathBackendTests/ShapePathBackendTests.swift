import Testing
@testable import ShapePathBackend

/// The identifier appears in every stored benchmark result. Changing it orphans past runs.
@Test
func identifierIsPinned() {
    #expect(ShapePathBackend.identifier == "shape-path")
}
