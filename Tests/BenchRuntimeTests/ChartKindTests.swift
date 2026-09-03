import Foundation
import Testing
@testable import BenchRuntime

@Test
func chartKindIsExtensibleWithoutEditingThisModule() {
    let custom = ChartKind(rawValue: "well-log-track")
    #expect(custom.rawValue == "well-log-track")
    #expect(custom != ChartKind.stripChart)
}

@Test
func referenceChartIdentifierIsPinned() {
    #expect(ChartKind.stripChart.rawValue == "strip-chart")
}

@Test
func capabilitySurvivesAResultFileRoundTrip() throws {
    let capability = Capability(
        kind: .stripChart,
        maxPoints: 100_000,
        refreshHz: 120,
        device: "iPhone17,1",
        measuredAt: Date(timeIntervalSince1970: 1_756_900_000)
    )
    let data = try JSONEncoder().encode(capability)
    let decoded = try JSONDecoder().decode(Capability.self, from: data)
    #expect(decoded == capability)
}
