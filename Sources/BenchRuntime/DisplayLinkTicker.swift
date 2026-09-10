#if os(iOS)
import QuartzCore

/// Display tick source backed by `CADisplayLink`.
///
/// The link holds its target, so the object that owns the link must invalidate it rather than
/// rely on deallocation: on iOS a pushed-away screen's `deinit` runs at an unpredictable later
/// point, and until it does the link keeps firing.
@MainActor
public final class DisplayLinkTicker: DisplayTicking {
    private final class Proxy: NSObject {
        var onTick: ((FrameTick) -> Void)?

        @objc func fire(_ link: CADisplayLink) {
            onTick?(
                FrameTick(
                    frameID: 0,  // assigned by FrameClock; the source does not number frames
                    targetTimestamp: link.targetTimestamp,
                    timestamp: link.timestamp
                )
            )
        }
    }

    /// The rate a measurement asks for: everything the display will give.
    ///
    /// Not `CAFrameRateRange.default`. That one leaves the choice to the system and the system
    /// chooses 60 Hz — measured on an iPhone 16 Pro, iOS 26.5.2, 10 September 2026: 59.60 Hz under
    /// the default range against 119.98 Hz under every explicit range tried, with the high frame
    /// rate opt-in already in place. A default that silently halves the frame rate is worse than
    /// no default, because the number it produces still looks like a measurement.
    ///
    /// A maximum above what the display can do is a ceiling on the request, not a claim about the
    /// hardware: asking for 240 on the same device produced 119.98 Hz, clamped rather than
    /// refused. The minimum is the floor every iOS display meets, and it is there to stop the
    /// system throttling down in the middle of a run.
    public static let displayMaximum = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)

    private let proxy = Proxy()
    private var link: CADisplayLink?

    /// Frame rate this ticker asks the system for. A measurement that reports a frame rate has to
    /// be able to say what it requested, because the system is free to give something else.
    public let preferredRange: CAFrameRateRange

    /// - Parameter preferredRange: Frame rate to request. Defaults to ``displayMaximum``.
    public init(preferredRange: CAFrameRateRange = DisplayLinkTicker.displayMaximum) {
        self.preferredRange = preferredRange
    }

    public func start(_ onTick: @escaping (FrameTick) -> Void) {
        guard link == nil else { return }
        proxy.onTick = onTick
        let created = CADisplayLink(target: proxy, selector: #selector(Proxy.fire(_:)))
        created.preferredFrameRateRange = preferredRange
        created.add(to: .main, forMode: .common)
        link = created
    }

    public func stop() {
        link?.invalidate()
        link = nil
        proxy.onTick = nil
    }

    // No `deinit` cleanup: it would have to touch main-actor state from a nonisolated context,
    // and on iOS deallocation happens at an unpredictable point after the screen is gone anyway.
    // Ownership rule instead: whoever starts a ticker stops it, in `onDisappear` or on entering
    // the background — never by dropping the reference and hoping.
}
#endif
