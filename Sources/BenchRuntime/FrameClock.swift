import Foundation

/// One display tick.
public struct FrameTick: Sendable, Equatable {
    /// Monotonic frame number for the scene. Every consumer of one clock sees the same number for
    /// the same tick — that identity is what lets two charts on one screen stay in step.
    public let frameID: UInt64
    /// When the frame being prepared is expected to appear, in seconds on the host clock.
    public let targetTimestamp: Double
    /// When the tick fired, in seconds on the host clock.
    public let timestamp: Double

    public init(frameID: UInt64, targetTimestamp: Double, timestamp: Double) {
        self.frameID = frameID
        self.targetTimestamp = targetTimestamp
        self.timestamp = timestamp
    }
}

/// A source of display ticks.
///
/// Behind a protocol so that tests drive frames by hand. A test that waits for a real display link
/// is a test that is slow, flaky and unable to describe the case it is checking.
///
/// Main-actor bound because that is where every real source delivers: `CADisplayLink` fires on the
/// run loop it was added to, and pretending otherwise would push an isolation hop into the one
/// place in the frame where there is no room for one.
@MainActor
public protocol DisplayTicking: AnyObject {
    /// Begins delivering ticks. Calling twice without ``stop()`` must be harmless.
    func start(_ onTick: @escaping (FrameTick) -> Void)
    /// Stops delivering ticks. Calling on a stopped source must be harmless.
    func stop()
}

/// The single tick for one scene, fanned out to everything that draws in it.
///
/// One clock per scene, never one per chart. Two renderers each running their own display link
/// drift apart within seconds: their cursors disagree, their windows show different instants, and
/// a comparison between them stops meaning anything. That is the failure this type exists to make
/// impossible, so advancing the clock is not part of its public surface — only the source can do
/// it, and drawing code has no way to reach it.
/// - SeeAlso: Docs/methods/frame-pipeline.md
@MainActor
public final class FrameClock {
    /// A registration. Hold it for as long as the observer should receive ticks, and pass it to
    /// ``unsubscribe(_:)`` to stop. Dropping it does **not** unsubscribe — the clock holds the
    /// closure, not the token.
    public struct Token: Hashable, Sendable {
        fileprivate let id: UInt64
    }

    private let source: any DisplayTicking
    private var observers: [UInt64: (FrameTick) -> Void] = [:]
    private var nextToken: UInt64 = 0
    private var frameID: UInt64 = 0
    private var running = false

    /// Most recent tick delivered, or `nil` before the first one.
    public private(set) var latest: FrameTick?

    public init(source: any DisplayTicking) {
        self.source = source
    }

    /// Registers an observer, starting the source on the first registration.
    ///
    /// The returned token is the only handle to the registration, so it is not discardable: a
    /// caller who drops it can never unsubscribe, the source runs for the life of the clock, and
    /// the teardown this type documents becomes unreachable.
    public func subscribe(_ body: @escaping (FrameTick) -> Void) -> Token {
        nextToken += 1
        let token = Token(id: nextToken)
        observers[token.id] = body
        if !running {
            running = true
            source.start { [weak self] tick in
                self?.deliver(tick)
            }
        }
        return token
    }

    /// Removes an observer, stopping the source once the last one goes.
    ///
    /// Stopping matters more than it looks: a display link left running behind a pushed-away
    /// screen keeps a GPU pipeline warm and a CPU busy for a view nobody is looking at.
    public func unsubscribe(_ token: Token) {
        observers.removeValue(forKey: token.id)
        if observers.isEmpty, running {
            running = false
            source.stop()
        }
    }

    /// Number of live observers. Exposed so a leak shows up as a number in a test.
    public var observerCount: Int { observers.count }

    private func deliver(_ raw: FrameTick) {
        frameID &+= 1
        let tick = FrameTick(
            frameID: frameID,
            targetTimestamp: raw.targetTimestamp,
            timestamp: raw.timestamp
        )
        latest = tick

        // Registration order, taken as a snapshot before the fan-out. Iterating `observers.values`
        // directly did neither: dictionary order varies with hash seeding, so two charts on one
        // clock touched a shared provider in a different order between launches — under a claim of
        // identical work — and an observer that unsubscribed from inside its own callback was
        // still called for that tick, because the iteration held the pre-removal storage.
        let ordered = observers.sorted { $0.key < $1.key }.map(\.value)
        for observer in ordered {
            observer(tick)
        }
    }
}
