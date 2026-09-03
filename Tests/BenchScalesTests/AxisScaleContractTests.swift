import BenchTestSupport
import Testing
@testable import BenchScales

/// Properties every scale must satisfy, checked against every scale.
///
/// The previous version of this file asserted that two hand-built `MapResult` literals differed
/// and that its own stub measurer multiplied correctly — both of which pass with every conformer
/// deleted. These do not.
private let measurer = FixedMetrics()

private func scales() -> [(name: String, scale: any AxisScale)] {
    [
        ("linear", LinearScale(domain: -50...150)),
        ("linear-negative", LinearScale(domain: -100_000...1)),
        ("time-seconds", TimeScale(domain: 0...10)),
        ("time-day", TimeScale(domain: 0...86_400)),
    ]
}

@Test
func mapNeverLeavesTheUnitInterval() {
    for (name, scale) in scales() {
        let span = scale.domain.upperBound - scale.domain.lowerBound
        for step in 0...200 {
            let value = scale.domain.lowerBound - span + Double(step) * span * 3 / 200
            let result = scale.map(value)
            #expect(result.normalised >= 0, "\(name) mapped below 0")
            #expect(result.normalised <= 1, "\(name) mapped above 1")
        }
    }
}

@Test
func everyScaleRoundTripsInsideItsDomain() {
    for (name, scale) in scales() {
        let span = scale.domain.upperBound - scale.domain.lowerBound
        for step in 0...100 {
            let value = scale.domain.lowerBound + Double(step) * span / 100
            let back = scale.invert(scale.map(value).normalised)
            #expect(abs(back - value) <= max(abs(value), 1) * 1e-9, "\(name) failed round trip")
        }
    }
}

@Test
func valuesOutsideTheDomainAreFlagged() {
    for (name, scale) in scales() {
        #expect(scale.map(scale.domain.lowerBound - 1).isOutOfDomain, "\(name) missed a low value")
        #expect(scale.map(scale.domain.upperBound + 1).isOutOfDomain, "\(name) missed a high value")
        #expect(scale.map(scale.domain.lowerBound).isOutOfDomain == false, "\(name) rejected its own bound")
    }
}

/// The cap the protocol promises. A caller sizing a label pool from `target` must not be handed
/// more than it asked for — and before this test, both scales could return one extra.
@Test
func tickCountNeverExceedsTheTarget() {
    for (name, scale) in scales() {
        for target in 2...12 {
            let count = scale.ticks(
                target: target,
                axisLength: 1_000,
                orientation: .horizontal,
                measuring: measurer
            ).count
            #expect(count <= target, "\(name) returned \(count) ticks for target \(target)")
        }
    }
}

@Test
func ticksAreOrderedAndInsideTheDomain() {
    for (name, scale) in scales() {
        let ticks = scale.ticks(target: 8, axisLength: 800, orientation: .horizontal, measuring: measurer)
        #expect(ticks.map(\.value) == ticks.map(\.value).sorted(), "\(name) returned unordered ticks")
        for tick in ticks {
            #expect(scale.domain.contains(tick.value), "\(name) placed a tick outside its domain")
        }
    }
}

/// Labels collide along their width on a horizontal axis and along their line height on a
/// vertical one. Measuring width against a plot's height thinned vertical axes by the wrong
/// dimension, which is why the orientation is part of the signature.
@Test
func aVerticalAxisFitsMoreLabelsThanAHorizontalOneOfTheSameLength() {
    let scale = LinearScale(domain: 0...100_000)
    let vertical = scale.ticks(target: 10, axisLength: 300, orientation: .vertical, measuring: measurer)
    let horizontal = scale.ticks(target: 10, axisLength: 300, orientation: .horizontal, measuring: measurer)
    #expect(vertical.count > horizontal.count)
}

/// The failing direction is always under-measurement, because the fitted count can only reduce
/// the caller's target. A domain whose longer label is the negative lower bound used to slip past.
@Test
func labelWidthIsMeasuredFromBothEndsOfTheDomain() {
    let scale = LinearScale(domain: -100_000...1)
    let ticks = scale.ticks(target: 6, axisLength: 100, orientation: .horizontal, measuring: measurer)
    let widest = ticks.map { measurer.width(of: $0.label) }.max() ?? 0
    #expect(Double(ticks.count) * widest <= 100 * 1.1)
}
