import Testing
@testable import ShaderBackend

/// The identifier appears in every stored benchmark result. Changing it orphans past runs.
@Test
func identifierIsPinned() {
    #expect(ShaderBackend.identifier == "shader")
}
