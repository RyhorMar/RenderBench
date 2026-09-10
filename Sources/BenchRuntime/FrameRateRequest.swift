import Foundation
import QuartzCore

/// The frame rate a display link is asked for, and the one thing standing in its way that this
/// process can see.
///
/// Two locks guard a high refresh rate, and closing one of them produces a plausible 60 Hz that
/// looks exactly like a measurement: the bundle key unlocks the range at all, and the range on the
/// link asks for it. Measured on an iPhone 16 Pro, iOS 26.5.2, 10 September 2026: without the key a
/// link pinned to 120 Hz still ticked at 59.99 Hz, and with the key but the system's default range
/// it ticked at 59.74 Hz. Only both together reached 119.98 Hz.
///
/// This is the one place that mapping is derived. It says nothing about what the run will get:
/// Low Power Mode, thermal state and the accessibility setting that limits the frame rate all
/// lower it afterwards, and the last of those cannot be read from inside the process at all.
/// What was got is ``FrameRateMeter``'s question.
public struct FrameRateRequest: Sendable, Equatable {
    /// What goes to the display link. Already clamped by the opt-in and by the display, so
    /// `range.maximum` is also how many hertz it is worth expecting.
    public let range: CAFrameRateRange
    /// True when the bundle caps this app below what the display can do. The only shortfall this
    /// value can see; the rest are invisible from inside the process.
    public let optInMissing: Bool

    /// - Parameters:
    ///   - displayMaximumFramesPerSecond: from `UIScreen.maximumFramesPerSecond`, passed in
    ///     because this module may not import UIKit. Anything below 60 is read as "the caller
    ///     could not tell" and treated as 60: no iOS display is slower.
    ///   - optedInToHighFrameRate: whether the bundle carries the opt-in key.
    public init(displayMaximumFramesPerSecond: Int, optedInToHighFrameRate: Bool) {
        let display = max(displayMaximumFramesPerSecond, 60)
        let capped = display > 60 && !optedInToHighFrameRate
        let ceiling = capped ? 60 : display
        range = CAFrameRateRange(
            minimum: Float(min(60, ceiling)),
            maximum: Float(ceiling),
            preferred: Float(ceiling)
        )
        optInMissing = capped
    }

    /// The same, reading `CADisableMinimumFrameDurationOnPhone` out of the main bundle.
    ///
    /// The trailing `OnPhone` is the whole key. An unrecognised Info.plist key is ignored without
    /// a word, which is how this app spent its whole life at half the rate it reported.
    public static func current(displayMaximumFramesPerSecond: Int) -> FrameRateRequest {
        let key = Bundle.main.object(forInfoDictionaryKey: "CADisableMinimumFrameDurationOnPhone")
        return FrameRateRequest(
            displayMaximumFramesPerSecond: displayMaximumFramesPerSecond,
            optedInToHighFrameRate: (key as? Bool) == true
        )
    }
}
