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

/// The tail is the reason the fixture exists: a mean over this vector reads as comfortable while
/// one frame in a hundred misses a 120 Hz budget by a factor of four.
@Test
func fixtureHasATailAMeanWouldHide() {
    let values = PercentileFixture.frameDurationsNs
    let mean = values.reduce(UInt64(0), +) / UInt64(values.count)
    #expect(mean < 8_300_000)
    #expect(PercentileFixture.expectedP99Ns > 8_300_000 * 3)
}
