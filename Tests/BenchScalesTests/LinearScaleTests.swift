import BenchTestSupport
import Testing
@testable import BenchScales

private let measurer = FixedMetrics(pointsPerCharacter: 7.0)

@Test
func roundTripIsExactToWithinOneMicro() {
    let scale = LinearScale(domain: -1_234.5...9_876.5)
    var worst = 0.0
    for step in 0...10_000 {
        let value = -1_234.5 + Double(step) * (9_876.5 + 1_234.5) / 10_000
        let back = scale.invert(scale.map(value).normalised)
        worst = max(worst, abs(back - value) / max(abs(value), 1))
    }
    #expect(worst < 1e-6)
}

@Test
func valuesOutsideTheDomainAreFlaggedAndClamped() {
    let scale = LinearScale(domain: 0...100)
    let below = scale.map(-5)
    let above = scale.map(105)
    #expect(below.isOutOfDomain)
    #expect(below.normalised == 0)
    #expect(above.isOutOfDomain)
    #expect(above.normalised == 1)
    #expect(scale.map(50).isOutOfDomain == false)
}

/// A collapsed domain has no proportion to report. Returning 0 would place every sample at the
/// bottom of the axis and look like data.
@Test
func collapsedDomainIsReportedRatherThanDrawn() {
    let scale = LinearScale(domain: 5...5)
    let result = scale.map(5)
    #expect(result.isOutOfDomain)
    #expect(scale.ticks(target: 5, axisLength: 400, orientation: .horizontal, measuring: measurer).isEmpty)
}

@Test
func ticksLandOnRoundNumbers() {
    let scale = LinearScale(domain: 0...100)
    // Six, not five: both ends of this domain land on a multiple of the step, so covering it
    // needs one more tick than there are intervals. Asking for five gets five — the target is a
    // cap, and a caller sizing a label pool from it must not be handed a sixth.
    let six = scale.ticks(target: 6, axisLength: 400, orientation: .horizontal, measuring: measurer)
    #expect(six.map(\.value) == [0, 20, 40, 60, 80, 100])

    let five = scale.ticks(target: 5, axisLength: 400, orientation: .horizontal, measuring: measurer)
    #expect(five.count == 5)
    #expect(five.map(\.value).allSatisfy { $0.truncatingRemainder(dividingBy: 20) == 0 })
}

@Test
func labelPrecisionFollowsTheStepNotTheValues() {
    let scale = LinearScale(domain: 0...1)
    let labels = scale.ticks(target: 4, axisLength: 400, orientation: .horizontal, measuring: measurer).map(\.label)
    #expect(labels.first == "0.00")
    #expect(labels.contains("0.25"))
}

/// A narrow axis cannot hold the labels a caller asks for. Honouring the request anyway is how
/// axes end up with overlapping text at exactly the zoom the reader cares about.
@Test
func labelCountIsCutToWhatTheAxisCanPhysicallyHold() {
    let scale = LinearScale(domain: 0...1_000_000)
    let wide = scale.ticks(target: 10, axisLength: 1_200, orientation: .horizontal, measuring: measurer).count
    let narrow = scale.ticks(target: 10, axisLength: 120, orientation: .horizontal, measuring: measurer).count
    #expect(narrow < wide)
    #expect(narrow >= 2)
}

@Test
func negativeZeroNeverReachesALabel() {
    let scale = LinearScale(domain: -1...1)
    let labels = scale.ticks(target: 4, axisLength: 400, orientation: .horizontal, measuring: measurer).map(\.label)
    #expect(labels.contains("-0") == false)
    #expect(labels.contains("-0.0") == false)
}
