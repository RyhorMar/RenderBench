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

    /// What this ticker asks the system for, and what stands in the way of it. A measurement that
    /// reports a frame rate has to be able to say what it requested, because the system is free to
    /// give something else — and to say so without deriving the request a second time.
    public let request: FrameRateRequest

    public init(request: FrameRateRequest) {
        self.request = request
    }

    public func start(_ onTick: @escaping (FrameTick) -> Void) {
        guard link == nil else { return }
        proxy.onTick = onTick
        let created = CADisplayLink(target: proxy, selector: #selector(Proxy.fire(_:)))
        created.preferredFrameRateRange = request.range
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
