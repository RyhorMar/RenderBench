import Testing
@testable import BenchTestSupport

/// Nearest-rank, computed here from the definition rather than reused from the implementation
/// under test. A fixture whose expected values come from the code they check proves nothing.
private func nearestRank(_ values: [UInt64], percentile: Double) -> UInt64 {
    let sorted = values.sorted()
    let rank = Int((percentile / 100.0 * Double(sorted.count)).rounded(.up))
    return sorted[max(1, min(rank, sorted.count)) - 1]
}

@Test
func fixtureMatchesItsStatedPercentiles() {
    let values = PercentileFixture.frameDurationsNs
    #expect(values.count == 100)
    #expect(nearestRank(values, percentile: 50) == PercentileFixture.expectedP50Ns)
    #expect(nearestRank(values, percentile: 95) == PercentileFixture.expectedP95Ns)
    #expect(nearestRank(values, percentile: 99) == PercentileFixture.expectedP99Ns)
    #expect(values.max() == PercentileFixture.expectedMaxNs)
}

/// The tail is the reason the fixture exists. A mean understates it by more than a factor of
/// three, and the median hides it entirely — which is why the results format publishes p99 and max
/// alongside p50 rather than a single average.
@Test
func fixtureHasATailThatOnlyThePercentilesReport() {
    let values = PercentileFixture.frameDurationsNs
    let mean = values.reduce(UInt64(0), +) / UInt64(values.count)

    #expect(PercentileFixture.expectedP50Ns < 8_300_000)
    #expect(mean < PercentileFixture.expectedP99Ns / 3)
    #expect(PercentileFixture.expectedP99Ns > 8_300_000 * 3)
}
