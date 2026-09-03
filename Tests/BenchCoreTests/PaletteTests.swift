import Foundation
import Testing
@testable import BenchCore

/// Anchors taken from the sRGB standard rather than recomputed from the implementation's own
/// formula. A test that evaluates the same expression twice proves only that the expression is
/// stable.
///
/// Mid-grey is the useful one: 50 % encoded sRGB is 21.6 % linear light, and getting that wrong is
/// the single most common colour bug — it is what makes a naive gradient darken through the middle.
@Test
func encodedToLinearMatchesTheStandardAtKnownPoints() {
    let black = PaletteColor(srgb: 0, 0, 0)
    let white = PaletteColor(srgb: 255, 255, 255)
    let midGrey = PaletteColor(srgb: 128, 128, 128)

    #expect(black.red == 0)
    #expect(abs(white.red - 1) < 1e-12)
    #expect(abs(midGrey.red - 0.2158) < 0.0005)
}

/// The transfer function is piecewise, and the join is where an implementation goes wrong: a
/// discontinuity there shows as a visible step in a dark gradient.
@Test
func theTransferFunctionIsContinuousAcrossItsJoin() {
    // 10/255 sits below the 0.04045 threshold, 11/255 just above it.
    let below = PaletteColor(srgb: 10, 10, 10).red
    let above = PaletteColor(srgb: 11, 11, 11).red
    #expect(above > below)
    #expect(above - below < 0.0005)
}

@Test
func conversionIsMonotonicAndStaysInRange() {
    var previous = -1.0
    for channel in 0...255 {
        let value = PaletteColor(srgb: channel, channel, channel).red
        #expect(value > previous, "not monotonic at \(channel)")
        #expect(value >= 0)
        #expect(value <= 1)
        previous = value
    }
}

@Test
func channelsAreIndependent() {
    let colour = PaletteColor(srgb: 255, 128, 0)
    #expect(abs(colour.red - 1) < 1e-12)
    #expect(abs(colour.green - 0.2158) < 0.0005)
    #expect(colour.blue == 0)
}

/// Eight distinct colours in each variant. The mutation that made every series share one colour
/// passed unnoticed before this existed, and a chart with eight identical curves is unreadable in
/// a way no other test would report.
@Test
func eachVariantHoldsEightDistinctColours() {
    for (name, set) in [("light", Palette.categoricalLight), ("dark", Palette.categoricalDark)] {
        #expect(set.count == 8, "\(name) has \(set.count) colours")
        #expect(Set(set).count == 8, "\(name) contains a duplicate")
    }
}

/// Separation in linear space. This does **not** demonstrate the palette's actual claim — that the
/// colours stay distinguishable under colour vision deficiency — which needs Machado's simulation
/// and CIEDE2000 and is not implemented. It catches the failure this test can catch: colours that
/// collapsed towards each other or towards one hue.
@Test
func noTwoColoursAreNearlyIdenticalInLinearSpace() {
    func distance(_ a: PaletteColor, _ b: PaletteColor) -> Double {
        let dr = a.red - b.red, dg = a.green - b.green, db = a.blue - b.blue
        return (dr * dr + dg * dg + db * db).squareRoot()
    }
    for set in [Palette.categoricalLight, Palette.categoricalDark] {
        var closest = Double.infinity
        for (i, first) in set.enumerated() {
            for second in set[(i + 1)...] {
                closest = min(closest, distance(first, second))
            }
        }
        #expect(closest > 0.05, "closest pair is \(closest) apart")
    }
}

@Test
func theDarkVariantIsNotTheLightOne() {
    for index in 0..<8 {
        let light = Palette.colour(forSeries: index, dark: false)
        let dark = Palette.colour(forSeries: index, dark: true)
        #expect(light != dark, "variant \(index) is identical in both themes")
    }
}

/// Cycling past eight is a deliberate compromise and a signal, so it must behave predictably
/// rather than trap or return an arbitrary hue.
@Test
func indicesWrapAroundInsteadOfTrapping() {
    #expect(Palette.colour(forSeries: 8, dark: false) == Palette.colour(forSeries: 0, dark: false))
    #expect(Palette.colour(forSeries: 15, dark: false) == Palette.colour(forSeries: 7, dark: false))
    #expect(Palette.colour(forSeries: 100, dark: true) == Palette.colour(forSeries: 4, dark: true))
}

/// A negative index reaches this through arithmetic on a series list; Swift's `%` keeps the sign,
/// so the naive form would index out of bounds and crash a running chart.
@Test
func negativeIndicesAreSafe() {
    #expect(Palette.colour(forSeries: -1, dark: false) == Palette.colour(forSeries: 7, dark: false))
    #expect(Palette.colour(forSeries: -8, dark: false) == Palette.colour(forSeries: 0, dark: false))
    #expect(Palette.colour(forSeries: -9, dark: true) == Palette.colour(forSeries: 7, dark: true))
}
