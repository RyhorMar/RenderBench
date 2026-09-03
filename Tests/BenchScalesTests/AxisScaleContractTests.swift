import Testing
@testable import BenchScales

private struct FixedWidthMeasurer: TextMeasuring {
    let perCharacter: Double
    func width(of text: String) -> Double { Double(text.count) * perCharacter }
}

@Test
func outOfDomainIsReportedRatherThanEncodedAsAClamp() {
    let inside = MapResult(normalised: 0.5, isOutOfDomain: false)
    let outside = MapResult(normalised: 0.0, isOutOfDomain: true)
    // A clamped value and a legitimate zero are indistinguishable by position alone; the flag is
    // the only thing that separates "at the bottom" from "has no image under this scale".
    #expect(inside.normalised != outside.normalised || inside.isOutOfDomain != outside.isOutOfDomain)
    #expect(outside.isOutOfDomain)
}

@Test
func textMeasuringIsSatisfiableWithoutUIFrameworks() {
    let measurer = FixedWidthMeasurer(perCharacter: 7.0)
    #expect(measurer.width(of: "1 000") == 35.0)
}
