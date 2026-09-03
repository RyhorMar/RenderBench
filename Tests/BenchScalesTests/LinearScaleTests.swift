import Testing
@testable import BenchScales

private struct FixedWidth: TextMeasuring {
    var perCharacter: Double = 7.0
    func width(of text: String) -> Double { Double(text.count) * perCharacter }
}

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
    #expect(scale.ticks(target: 5, axisLength: 400, measuring: FixedWidth()).isEmpty)
}

@Test
func ticksLandOnRoundNumbers() {
    let scale = LinearScale(domain: 0...100)
    let values = scale.ticks(target: 5, axisLength: 400, measuring: FixedWidth()).map(\.value)
    #expect(values == [0, 20, 40, 60, 80, 100])
}

@Test
func labelPrecisionFollowsTheStepNotTheValues() {
    let scale = LinearScale(domain: 0...1)
    let labels = scale.ticks(target: 4, axisLength: 400, measuring: FixedWidth()).map(\.label)
    #expect(labels.first == "0.00")
    #expect(labels.contains("0.25"))
}

/// A narrow axis cannot hold the labels a caller asks for. Honouring the request anyway is how
/// axes end up with overlapping text at exactly the zoom the reader cares about.
@Test
func labelCountIsCutToWhatTheAxisCanPhysicallyHold() {
    let scale = LinearScale(domain: 0...1_000_000)
    let wide = scale.ticks(target: 10, axisLength: 1_200, measuring: FixedWidth()).count
    let narrow = scale.ticks(target: 10, axisLength: 120, measuring: FixedWidth()).count
    #expect(narrow < wide)
    #expect(narrow >= 2)
}

@Test
func negativeZeroNeverReachesALabel() {
    let scale = LinearScale(domain: -1...1)
    let labels = scale.ticks(target: 4, axisLength: 400, measuring: FixedWidth()).map(\.label)
    #expect(labels.contains("-0") == false)
    #expect(labels.contains("-0.0") == false)
}
