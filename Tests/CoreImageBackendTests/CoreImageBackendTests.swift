import Testing
@testable import CoreImageBackend

/// The identifier appears in every stored benchmark result. Changing it orphans past runs.
@Test
func identifierIsPinned() {
    #expect(CoreImageBackend.identifier == "core-image")
}
