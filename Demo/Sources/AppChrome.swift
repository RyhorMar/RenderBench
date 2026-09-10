import SwiftUI

/// The app's chrome colours, one name per role rather than one per hex.
///
/// They come from the asset catalogue rather than from literals so that the light and dark values
/// of a role live together and the system, not this code, decides which one a view gets. The
/// symbols below are the ones the asset compiler generates: a catalogue missing from the target
/// fails the build here instead of quietly rendering every surface grey.
///
/// Cool slate, and deliberately not the warm stone of the project's web page: the two surfaces
/// were designed as different families, and averaging them would produce a third that neither
/// design asked for.
enum AppChrome {
    /// Behind everything.
    static let page = Color(.page)
    /// A card or grouped row, one step in front of ``page``.
    static let card = Color(.card)
    /// Primary text.
    static let ink = Color(.ink)
    /// Muted labels — a unit beside a number, a caption.
    ///
    /// **Not usable for body text at body size.** Measured against the three grounds of its own
    /// theme: 4.07:1 on ``page``, 4.62:1 on ``card``, 3.89:1 on ``chip`` in light; 5.28 / 4.78 /
    /// 4.40 in dark. The floor for normal-size text is 4.5:1, so four of those six fail it. All six
    /// clear 3:1, which is the floor for large text — 18 pt, or 14 pt bold — and for non-text
    /// graphics. Use it there, and use ``sub2`` where a sentence has to be read.
    static let sub = Color(.sub)
    /// Secondary body text: dimmer than ``ink``, still meant to be read.
    static let sub2 = Color(.sub2)
    /// Hairlines and card edges.
    ///
    /// Decorative by design and measured as such: 1.16:1 to 1.42:1 against the grounds it is drawn
    /// on. Nothing may depend on seeing it — a control whose boundary is the only thing separating
    /// it from the page needs its own contrast, not this.
    static let border = Color(.border)
    /// The provenance chip's ground.
    static let chip = Color(.chip)

    /// The one interactive colour: a control that is on, a link.
    ///
    /// Its source names `oklch(0.5 0.13 220)` for light and `oklch(0.75 0.13 195)` for dark, and
    /// **neither is representable in sRGB** — the red channel of both is negative, and the light one
    /// falls outside Display P3 as well. What ships is each colour mapped into sRGB by the CSS
    /// Color 4 gamut-mapping algorithm — chroma reduced at constant lightness and hue, then clipped
    /// once the clipped colour is within an Oklab just-noticeable difference — because that is the
    /// mapping a browser performs, and the design these values come from was reviewed in one.
    /// Measured cost against the colour as named: ΔE2000 3.7 for light, 0.24 for dark. Contrast
    /// against the surfaces of its own theme: 4.71:1 light, 7.71:1 dark.
    static let accent = Color(.accent)
}
