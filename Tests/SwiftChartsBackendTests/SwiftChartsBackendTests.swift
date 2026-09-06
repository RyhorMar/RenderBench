import Testing
@testable import SwiftChartsBackend

/// The identifier appears in every stored benchmark result. Changing it orphans past runs.
@Test
func identifierIsPinned() {
    #expect(SwiftChartsBackend.identifier == "swift-charts")
}
