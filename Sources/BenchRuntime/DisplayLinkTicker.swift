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

    private let proxy = Proxy()
    private var link: CADisplayLink?
    private let preferredRange: CAFrameRateRange

    /// - Parameter preferredRange: Frame rate to request. The default lets the system choose,
    ///   which on a ProMotion device means the range is decided by what else is on screen; a
    ///   benchmark pins it explicitly instead.
    public init(preferredRange: CAFrameRateRange = .default) {
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
