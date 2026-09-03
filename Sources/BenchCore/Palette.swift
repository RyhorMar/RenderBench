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

/// Categorical colours for series that have no natural order.
///
/// Eight is the limit on purpose: beyond that, colour stops identifying anything and the series
/// need direct labels instead. The set is chosen to stay separable under the common forms of
/// colour vision deficiency, which rules out the red/green pairing that most default palettes open
/// with.
///
/// - SeeAlso: Docs/methods/colour.md — the sources this set follows, and why "CVD-safe" is
///   currently a claim inherited from them rather than one measured here.
public enum Palette {
    /// Eight categorical colours for a light background.
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
}
