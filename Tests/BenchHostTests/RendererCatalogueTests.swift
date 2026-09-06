import BenchHost
import BenchRuntime
import SwiftUI
import Testing

@MainActor
final class NullRenderer: ChartRenderer {
    static let descriptor = RendererDescriptor(identifier: "null", displayName: "Null", reportsRasterTime: false, reportsGPUTime: false)
    static let capabilities: [Capability] = []
    private(set) var encoded = 0
    private(set) var tornDown = false
    init() {}
    func encode(_ frame: PreparedFrame) -> EncodeReport { encoded += 1; return EncodeReport(encodeNs: 0, pointsDrawn: 0, drawCalls: 0) }
    var encodedRevision: UInt64 { UInt64(encoded) }
    func takeDeferredTimes() -> DeferredTimes { .none }
    var surface: AnyView { AnyView(EmptyView()) }
    func suspend() {}
    func resume() {}
    func teardown() { tornDown = true }
}

@MainActor @Test
func anEntryMakesAFreshRendererEachTime() {
    let entry = RendererEntry(NullRenderer.self)
    let a = entry.make(), b = entry.make()
    #expect(a !== b)
    #expect(entry.id == "null")
}
