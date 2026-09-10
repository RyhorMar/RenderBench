import BenchCore
import Testing
@testable import RenderBenchDemo

/// The rule the pill carries: colour distinguishes three families, the name identifies. A pill
/// without its word would claim a distinction three colours cannot make across nine methods.
@Test
func everyFamilyHasAWordAndTheyAreAllDifferent() {
    let names = RasteriserFamily.allCases.map(FamilyPill.name(of:))
    #expect(names.count == 3)
    #expect(Set(names).count == 3)
    #expect(names.allSatisfy { $0.isEmpty == false })
}

/// The words themselves, written out: they are the ones the design and the showcase use, and a
/// synonym here would quietly split one family into two vocabularies.
@Test
func theWordsAreTheOnesTheDesignUses() {
    #expect(FamilyPill.name(of: .sharedRasteriser) == "shared rasteriser")
    #expect(FamilyPill.name(of: .ownPipeline) == "own pipeline")
    #expect(FamilyPill.name(of: .hybrid) == "hybrid")
}

/// The pill's colour comes from the measured palette rather than from a literal beside it, so a
/// family cannot end up one colour in a legend and another on a card.
@Test
func theColourComesFromThePaletteAndNotFromTheView() {
    #expect(Palette.colour(for: .sharedRasteriser) == PaletteColor(srgb: 0xEE, 0x14, 0x01))
    #expect(Palette.colour(for: .ownPipeline) == PaletteColor(srgb: 0x04, 0x98, 0x63))
    #expect(Palette.colour(for: .hybrid) == PaletteColor(srgb: 0x6D, 0x65, 0xFE))
}
