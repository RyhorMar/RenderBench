import Testing
@testable import BenchGenerators

@Test
func oneSeedProducesOneStream() {
    var first = SplitMix64(seed: 0x0BAD_C0FF_EE0D_D00D)
    var second = SplitMix64(seed: 0x0BAD_C0FF_EE0D_D00D)
    for _ in 0..<1_000 {
        #expect(first.next() == second.next())
    }
}

@Test
func differentSeedsDiverseImmediately() {
    var a = SplitMix64(seed: 1)
    var b = SplitMix64(seed: 2)
    #expect(a.next() != b.next())
}

/// Zero is a legal seed. Generators that degenerate on it fail here rather than in a benchmark.
@Test
func zeroSeedIsUsable() {
    var generator = SplitMix64(seed: 0)
    let values = (0..<8).map { _ in generator.next() }
    #expect(Set(values).count == values.count)
}
