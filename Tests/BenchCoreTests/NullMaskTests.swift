import Testing
@testable import BenchCore

private func mask(_ pattern: [Bool]) -> NullMask {
    var result = NullMask(capacity: max(pattern.count, 1))
    for isGap in pattern { result.push(isGap: isGap) }
    return result
}

/// The stated acceptance property: one segment per uninterrupted stretch of measurements.
@Test
func segmentCountEqualsTheNumberOfUninterruptedStretches() {
    #expect(mask([false, false, false]).segments() == [0..<3])
    #expect(mask([true, true]).segments() == [])
    #expect(mask([false, true, false]).segments() == [0..<1, 2..<3])
    #expect(mask([true, false, false, true, false]).segments() == [1..<3, 4..<5])
}

@Test
func gapsAtTheEdgesDoNotProduceEmptySegments() {
    #expect(mask([true, false]).segments() == [1..<2])
    #expect(mask([false, true]).segments() == [0..<1])
}

@Test
func maskRotatesWithTheDataItDescribes() {
    var subject = NullMask(capacity: 3)
    subject.push(isGap: true)
    subject.push(isGap: false)
    subject.push(isGap: false)
    #expect(subject.segments() == [1..<3])
    // The gap falls out of the window; what remains is one uninterrupted stretch.
    subject.push(isGap: false)
    #expect(subject.segments() == [0..<3])
}
