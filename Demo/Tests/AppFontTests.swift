import Testing
import UIKit
@testable import RenderBenchDemo

/// Every bundled face resolves by name.
///
/// This is the test that fails when a file is missing from the target, missing from `UIAppFonts`, or
/// named by a PostScript name that does not exist — three separate mistakes with one symptom, and
/// the symptom is invisible on screen: the label draws in the system font and looks deliberate.
@Test
func everyBundledFaceIsRegistered() {
    for name in AppFont.all {
        #expect(UIFont(name: name, size: 12) != nil, "\(name) did not resolve")
    }
}

/// Resolving is not enough on its own: a name the system cannot find would give `nil`, but a name it
/// resolves to the wrong family would give a font. So the family is checked too.
@Test
func theResolvedFacesAreTheTwoPlexFamilies() {
    for name in [AppFont.sansRegular, AppFont.sansMedium, AppFont.sansSemiBold] {
        #expect(UIFont(name: name, size: 12)?.familyName == AppFont.sansFamily, "\(name)")
    }
    for name in [AppFont.monoRegular, AppFont.monoMedium, AppFont.monoSemiBold] {
        #expect(UIFont(name: name, size: 12)?.familyName == AppFont.monoFamily, "\(name)")
    }
}

/// The mono faces have to be monospaced, which is the property the design actually relies on: every
/// number in this app is a column that must not jitter as digits change.
@Test
func theMonoFacesAdvanceEveryDigitEqually() {
    for name in [AppFont.monoRegular, AppFont.monoMedium, AppFont.monoSemiBold] {
        guard let font = UIFont(name: name, size: 12) else {
            Issue.record("\(name) did not resolve")
            continue
        }
        let widths = Set("0123456789".map { character -> Double in
            let text = String(character) as NSString
            return text.size(withAttributes: [.font: font]).width
        })
        #expect(widths.count == 1, "\(name) advances digits differently: \(widths)")
    }
}

/// Six faces, not the eighteen the download contains. Italics and the other weights are bundle
/// weight the design does not use, and the list is what a reviewer checks against the design.
@Test
func exactlySixFacesAreBundled() {
    #expect(AppFont.all.count == 6)
    #expect(Set(AppFont.all).count == 6)
}
