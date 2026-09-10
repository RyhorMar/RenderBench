import BenchCore
import Testing
@testable import RenderBenchDemo

/// The chart's ground is the card it lies on, and the expected values are written out here rather
/// than read from the same asset the code reads: a test that fetches both sides from one source
/// proves the fetch works, not that the mapping is right.
@Test
func theChartIsGroundedOnTheCardItSitsIn() {
    #expect(AppChrome.chart(dark: false).background == PaletteColor(srgb: 0xFF, 0xFF, 0xFF))
    #expect(AppChrome.chart(dark: true).background == PaletteColor(srgb: 0x15, 0x19, 0x20))
}

/// Each role takes the app token that carries the same weight elsewhere. Swapping two of them is the
/// mutation this catches: a grid drawn in the label colour would be a chart with four bold lines
/// across it, and nothing else in the suite would notice.
@Test
func everyPieceOfFurnitureTakesItsOwnToken() {
    let light = AppChrome.chart(dark: false)
    #expect(light.grid == PaletteColor(srgb: 0xD7, 0xDC, 0xE2))
    #expect(light.axis == PaletteColor(srgb: 0x6B, 0x76, 0x84))
    #expect(light.label == PaletteColor(srgb: 0x3E, 0x48, 0x54))

    let dark = AppChrome.chart(dark: true)
    #expect(dark.grid == PaletteColor(srgb: 0x26, 0x2E, 0x38))
    #expect(dark.axis == PaletteColor(srgb: 0x7C, 0x86, 0x95))
    #expect(dark.label == PaletteColor(srgb: 0xAA, 0xB2, 0xBE))
}

/// The two themes must not collapse into one. A resolver that ignores the trait it is handed returns
/// the light values twice, which looks fine in the light theme and wrong everywhere else.
@Test
func theTwoThemesResolveToDifferentFurniture() {
    #expect(AppChrome.chart(dark: false) != AppChrome.chart(dark: true))
}
