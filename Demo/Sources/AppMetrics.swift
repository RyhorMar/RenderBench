import CoreGraphics
import SwiftUI

/// The app's size tokens: radii, paddings and the type scale its screens are drawn on.
///
/// Separate from the web page's own set on purpose. The two surfaces were designed as different
/// families — the page has no 14 pt radius and no 6 pt one, this surface has no 4 pt and no 3 pt —
/// and a single shared scale would be a fourth design that neither reference shows.
///
/// Units are points, and the design states them in CSS pixels at scale 1, where the two coincide.
enum AppMetrics {
    /// The four corner radii this surface uses, and there are no others.
    ///
    /// The appearance switch looks like a fifth and is not: a pill's radius is half its own height,
    /// so it follows the control's size rather than a token.
    enum Radius {
        /// Cards, list rows, stat tiles.
        static let card: CGFloat = 14
        /// Provenance chips and kind pills.
        static let chip: CGFloat = 6
        /// The method dot, 9 × 9 pt.
        static let dot: CGFloat = 2
        /// The live chart's rectangle.
        static let chart: CGFloat = 12
    }

    /// Insets in SwiftUI's own order — top, leading, bottom, trailing — so a caller reads them the
    /// way it applies them.
    ///
    /// The design gives ranges — 10–14 by 12–16 for a card, 2–3 by 6–8 for a chip — because its
    /// instances differ. A token cannot be a range, so each of these is the value the reference
    /// screens actually use inside that range, not its midpoint.
    enum Padding {
        /// A card that holds a section of a screen.
        static let card = EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14)
        /// A row in the backends list, one step tighter than a card.
        static let row = EdgeInsets(top: 10, leading: 13, bottom: 10, trailing: 13)
        /// A provenance chip, which sits beside a number rather than containing a block.
        static let chip = EdgeInsets(top: 3, leading: 8, bottom: 3, trailing: 8)
        /// A chip that is a control rather than a label, and so has to be worth aiming at. Not
        /// `chip` above: three points of vertical padding around a 12 pt name is an 18 pt target,
        /// and a row of nine of those is a row nobody can hit.
        static let controlChip = EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10)
    }

    /// Every size that appears on the app's screens, largest first.
    ///
    /// Held as a list, not as thirteen names, because the design names a role for only some of
    /// them: inventing a name for the rest would put a decision in code that the design has not
    /// made. A screen picks from this list; nothing picks a size that is not in it.
    enum TypeScale {
        static let sizes: [CGFloat] = [34, 22, 20, 18, 16, 14, 13, 12.5, 12, 11.5, 11, 10, 9]

        /// The large title, on the root screen and nowhere else.
        static let largeTitle: CGFloat = 34
        /// The workhorse label size — the most common size on these screens by a wide margin.
        static let label: CGFloat = 10

        /// Headings.
        static let headlineWeight: Font.Weight = .semibold
        /// Numbers, which are this project's main typographic element.
        static let numberWeight: Font.Weight = .medium
        /// Everything else.
        static let bodyWeight: Font.Weight = .regular

        /// Uppercase mono labels above a heading: tracking as a fraction of the size, applied by a
        /// caller that knows the size it is drawing at.
        ///
        /// The most frequent value on the reference screens, counted rather than chosen: 0.12 four
        /// times against 0.1 twice. The same rule as the paddings above, and for the same reason —
        /// the midpoint of the stated 0.08–0.12 range is a number no screen uses.
        static let eyebrowTracking: CGFloat = 0.12
    }
}
