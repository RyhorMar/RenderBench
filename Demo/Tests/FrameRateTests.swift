import BenchRuntime
import Foundation
import QuartzCore
import Testing
import UIKit

/// The exact spelling of the high frame rate opt-in.
///
/// This is the test for a mistake that has no symptom: an Info.plist key the system does not know
/// is ignored without a word, so the app keeps running — at half the frame rate, producing frame
/// times that look like measurements and describe a mode the release will never be in. The app
/// shipped with `CADisableMinimumFrameDuration`, one word short of the real key, and every
/// reading taken before this test existed was a 60 Hz reading labelled 120 Hz.
@Test
func theHighFrameRateOptInKeyIsSpelledTheWayTheSystemReadsIt() {
    let info = Bundle.main.infoDictionary ?? [:]
    #expect(info["CADisableMinimumFrameDurationOnPhone"] as? Bool == true)
}

/// The near miss itself. Checked separately because the key above being right does not mean the
/// wrong one is gone, and a leftover pair reads as deliberate to the next person.
@Test
func noNearMissSpellingOfThatKeySurvivesInTheBundle() {
    let info = Bundle.main.infoDictionary ?? [:]
    let related = info.keys.filter { $0.hasPrefix("CADisableMinimumFrameDuration") }
    #expect(related == ["CADisableMinimumFrameDurationOnPhone"], "found \(related.sorted())")
}

/// The other half of the same defect: the key alone does not raise the frame rate.
///
/// With the key in place and `CAFrameRateRange.default` on the link, an iPhone 16 Pro ticked at
/// 59.60 Hz; the same device under an explicit range ticked at 119.98 Hz. So the default the app
/// takes has to be an explicit range, and a change back to `.default` has to fail here rather
/// than in a results file six weeks later.
@MainActor
@Test
func theTickerAsksForTheDisplaysHighestRateByDefault() {
    let requested = DisplayLinkTicker().preferredRange
    #expect(requested.preferred == 120)
    #expect(requested.maximum == 120)
    #expect(requested.minimum == 60)
    #expect(requested != .default)
}
