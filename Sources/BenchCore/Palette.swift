import Foundation
/// A colour, as linear sRGB components in `0...1`.
///
/// Its own type rather than a platform colour so that the core stays free of UI frameworks, and
/// linear rather than gamma-encoded so that interpolating two colours does not pass through the
/// muddy band that blending encoded values produces.
public struct PaletteColor: Sendable, Hashable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// The same components gamma-encoded back into sRGB.
    ///
    /// Needed wherever a colour crosses into an API that expects encoded values — `CGColor` and
    /// most platform colour types do. Passing linear components to one of those darkens every
    /// colour, which is visible rather than subtle: it was how the first offscreen reference image
    /// came out looking nothing like the same chart on screen.
    public var encodedSRGB: (red: Double, green: Double, blue: Double) {
        (Self.encode(red), Self.encode(green), Self.encode(blue))
    }

    /// Inverse of the transfer function in ``init(srgb:_:_:)``, to the same standard.
    static func encode(_ linear: Double) -> Double {
        let clamped = min(max(linear, 0), 1)
        return clamped <= 0.003_130_8
            ? clamped * 12.92
            : 1.055 * pow(clamped, 1 / 2.4) - 0.055
    }

    /// Builds a colour from an 8-bit gamma-encoded sRGB triple, converting to linear.
    public init(srgb red: Int, _ green: Int, _ blue: Int) {
        func linear(_ channel: Int) -> Double {
            let value = Double(channel) / 255
            return value <= 0.040_45 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        self.init(red: linear(red), green: linear(green), blue: linear(blue))
    }
}

/// The rasteriser lineage a backend belongs to: which code turns geometry into pixels.
///
/// Three of them because that is the distinction the benchmark measures — a backend either hands
/// its geometry to the shared rasteriser, drives its own pipeline down to the pixels, or does one
/// for the curve and the other for the chrome around it. Method identity is carried by the
/// method's name and number, never by this.
public enum RasteriserFamily: Sendable, Hashable, CaseIterable {
    /// Geometry goes to Core Graphics, which produces the pixels.
    case sharedRasteriser
    /// The backend owns a device and produces the pixels itself.
    case ownPipeline
    /// Its own device delivers a frame the shared rasteriser drew.
    case hybrid
}

/// Colours for series, and for the rasteriser families the backends fall into.
///
/// The series set is eight colours, and its separability under colour vision deficiency has been
/// measured and refuted: the worst pair is 3.3 in the light variant and 0.2 in the dark one, where
/// the project's own floor is 15. No other eight colours would pass either — at that floor the
/// largest set that fits is seven — so series colour is a viewing aid, and a series without a
/// label beside it is not identified.
///
/// The family set is three colours, which does clear the floor. Three is what fits, and it is also
/// the distinction the project measures: which rasteriser produces the pixels.
///
/// - SeeAlso: Docs/methods/colour.md — the measurements, their thresholds, and what each set does
///   and does not claim.
public enum Palette {
    /// Eight categorical colours for a light background, separable at a glance and not under
    /// simulated colour vision deficiency.
    public static let categoricalLight: [PaletteColor] = [
        PaletteColor(srgb: 0x00, 0x6B, 0xA6),
        PaletteColor(srgb: 0xE3, 0x6C, 0x09),
        PaletteColor(srgb: 0x00, 0x8E, 0x7A),
        PaletteColor(srgb: 0xB5, 0x28, 0x5F),
        PaletteColor(srgb: 0x6A, 0x4C, 0x93),
        PaletteColor(srgb: 0x8A, 0x6D, 0x00),
        PaletteColor(srgb: 0x4F, 0x6B, 0x7A),
        PaletteColor(srgb: 0xC1, 0x44, 0x2E),
    ]

    /// The same hues lifted for a dark background, where the light set loses contrast.
    public static let categoricalDark: [PaletteColor] = [
        PaletteColor(srgb: 0x5B, 0xB0, 0xE8),
        PaletteColor(srgb: 0xFF, 0x9E, 0x4A),
        PaletteColor(srgb: 0x3F, 0xC9, 0xB0),
        PaletteColor(srgb: 0xF0, 0x72, 0xA8),
        PaletteColor(srgb: 0xB0, 0x94, 0xE8),
        PaletteColor(srgb: 0xD4, 0xB4, 0x3C),
        PaletteColor(srgb: 0x9A, 0xB4, 0xC4),
        PaletteColor(srgb: 0xFF, 0x8A, 0x75),
    ]

    /// Colour for a series index, cycling once the categorical set runs out.
    ///
    /// Cycling is a deliberate compromise and a signal: if a chart reaches it, colour is no longer
    /// identifying series and the caller should be labelling them directly.
    public static func colour(forSeries index: Int, dark: Bool) -> PaletteColor {
        let set = dark ? categoricalDark : categoricalLight
        return set[((index % set.count) + set.count) % set.count]
    }

    /// Colour for a rasteriser family — one set, both themes.
    ///
    /// Searched under Machado's colour vision deficiency model and CIEDE2000 against the floor of
    /// 15 this project sets itself, and measured on the values below: the worst pair is 17.2 under
    /// deuteranopia, 21.0 under protanopia, 17.3 under tritanopia, 47.5 for normal vision. Each
    /// clears 3:1 against every surface of both themes, which is why one set serves both rather
    /// than a light and a dark variant.
    ///
    /// The search ran in `oklch` at equal lightness 0.600 — hues 30, 160 and 280 — so that no
    /// family reads as more important than another. These are the rounded 8-bit values, fixed once
    /// here rather than re-derived: rounding costs 0.1 of the worst pair, 17.3 before and 17.2
    /// after, and the figures above are the ones measured after it. All three sit inside the sRGB
    /// gamut, which was checked and not assumed: a colour outside it is clamped channel by channel
    /// on the way in, and a clamped colour is a different colour from the one named.
    ///
    /// Never the only carrier of the distinction: the family's name belongs beside the colour.
    public static func colour(for family: RasteriserFamily) -> PaletteColor {
        switch family {
        case .sharedRasteriser: PaletteColor(srgb: 0xEE, 0x14, 0x01)
        case .ownPipeline: PaletteColor(srgb: 0x04, 0x98, 0x63)
        case .hybrid: PaletteColor(srgb: 0x6D, 0x65, 0xFE)
        }
    }
}
