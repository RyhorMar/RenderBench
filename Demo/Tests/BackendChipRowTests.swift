import BenchCore
import Testing
import SwiftUI
import UIKit
@testable import RenderBenchDemo

/// The catalogue and the family table are one list, so they cannot drift.
@MainActor
@Test
func everyBackendInTheCatalogueCarriesAFamily() {
    #expect(Catalogue.rows.map(\.id) == Catalogue.renderers.map(\.id))
    #expect(Catalogue.rows.count == 9)
    #expect(Set(Catalogue.rows.map(\.id)).count == 9)
}

/// Three families and nothing finer, and each of them is actually used.
///
/// A family nobody belongs to would mean the colour set says more than the code does; a tenth
/// value would mean the colour set says less.
@MainActor
@Test
func theFamiliesUsedAreExactlyTheThreeTheColourSetHas() {
    #expect(Set(Catalogue.rows.map(\.family)) == Set(RasteriserFamily.allCases))
}

/// The measurement the chip row exists for.
///
/// Nine names side by side need more width than a phone has, so a nine-segment control could only
/// have shown them by cutting them. If this ever stops being true — shorter names, fewer backends —
/// the control that replaced the picker should be reconsidered rather than kept out of habit.
@MainActor
@Test
func theNineNamesDoNotFitAcrossOneScreen() {
    let font = UIFont(name: AppFont.sansRegular, size: 12)
    let names = Catalogue.rows.map(\.entry.descriptor.displayName)
    // Chip chrome per name: the 9 pt dot, the 6 pt gap beside it, and the horizontal padding.
    let chrome = 9 + 6 + AppMetrics.Padding.controlChip.leading + AppMetrics.Padding.controlChip.trailing
    let total = names.reduce(0.0) { running, name in
        running + (name as NSString).size(withAttributes: [.font: font as Any]).width + chrome
    } + Double(names.count - 1) * 6
    // 440 pt is wider than any iPhone in portrait, so the claim does not depend on which one.
    #expect(total > 440, "nine names took \(total) pt")
}

/// No chip is narrower than the name it carries.
///
/// This is the claim the whole component exists to make, and it is the one an eye check makes
/// badly: a name cut at the right edge with an ellipsis looks deliberate. Measured instead — the
/// chip's own intrinsic width against the width the text needs at the size the chip draws it,
/// plus the chrome around it. A `lineLimit` or a fixed width added to the label fails here.
@MainActor
@Test
func noChipIsNarrowerThanTheNameItCarries() throws {
    let font = try #require(UIFont(name: AppFont.sansRegular, size: BackendChip.nameSize))
    let chrome = 9 + 6
        + AppMetrics.Padding.controlChip.leading + AppMetrics.Padding.controlChip.trailing
    for row in Catalogue.rows {
        let host = UIHostingController(
            rootView: BackendChip(row: row, isSelected: false, onTap: {})
        )
        let measured = host.sizeThatFits(in: CGSize(width: 10_000, height: 10_000)).width
        let name = row.entry.descriptor.displayName
        let needed = (name as NSString).size(withAttributes: [.font: font]).width + chrome
        #expect(measured >= needed - 1, "\(name): chip \(measured) pt against \(needed) pt needed")
    }
}
