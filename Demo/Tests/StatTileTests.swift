import Testing
@testable import RenderBenchDemo

/// The substitution the tile exists to prevent. A zero in place of an absent figure is not a
/// rounding of the truth: it claims the cheapest row in any comparison it appears in, and it looks
/// like a measurement to every reader.
@Test
func aReadingWithNothingToReportIsNilAndNotZero() {
    #expect(Reading.text(nil) == "nil")
    #expect(Reading.text(nil) != "0")
}

/// The other direction, and the one a careless fix breaks: a real zero is a measurement and stays
/// one. A backend that counted zero dropped frames has something to say.
@Test
func aRealZeroIsShownAsZero() {
    #expect(Reading.text("0") == "0")
}

/// An empty string is not absence either — it is a caller that formatted nothing, and quietly
/// turning it into `nil` would hide that mistake behind a legitimate-looking word.
@Test
func anEmptyReadingIsNotTurnedIntoAbsence() {
    #expect(Reading.text("") == "")
}

/// The tile's own two decisions: which words it shows, and whether it colours them as absence. The
/// colour is what a reader scanning a column of tiles sees before reading any of them.
@MainActor
@Test
func theTileSaysAndColoursAbsenceAsAbsence() {
    let missing = StatTile(reading: nil, label: "draw calls", provenance: .notMeasured)
    #expect(missing.text == Reading.absent)
    #expect(missing.isAbsent)

    let measured = StatTile(reading: "0", label: "dropped",
                            provenance: .observation(environment: "simulator"))
    #expect(measured.text == "0")
    #expect(measured.isAbsent == false)
}
