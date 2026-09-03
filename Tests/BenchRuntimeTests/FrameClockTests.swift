import Testing
@testable import BenchRuntime

/// Frames driven by hand, so a test states the sequence it checks instead of waiting for a screen.
@MainActor
private final class ManualTicker: DisplayTicking {
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private var onTick: ((FrameTick) -> Void)?

    var isRunning: Bool { onTick != nil }

    func start(_ onTick: @escaping (FrameTick) -> Void) {
        guard self.onTick == nil else { return }
        self.onTick = onTick
        startCount += 1
    }

    func stop() {
        guard onTick != nil else { return }
        onTick = nil
        stopCount += 1
    }

    func fire(at timestamp: Double, target: Double) {
        onTick?(FrameTick(frameID: 0, targetTimestamp: target, timestamp: timestamp))
    }
}

/// The property the whole design exists for: one tick per scene. Two renderers on one screen must
/// see the same frame number, or their cursors and windows drift apart within seconds.
@Test @MainActor
func twoConsumersSeeTheSameFrameNumber() {
    let ticker = ManualTicker()
    let clock = FrameClock(source: ticker)

    var left: [UInt64] = []
    var right: [UInt64] = []
    _ = clock.subscribe { left.append($0.frameID) }
    _ = clock.subscribe { right.append($0.frameID) }

    for step in 1...5 {
        ticker.fire(at: Double(step) / 120, target: Double(step + 1) / 120)
    }

    #expect(left == [1, 2, 3, 4, 5])
    #expect(left == right)
}

@Test @MainActor
func frameNumbersAreAssignedByTheClockNotBySource() {
    let ticker = ManualTicker()
    let clock = FrameClock(source: ticker)
    var seen: [UInt64] = []
    _ = clock.subscribe { seen.append($0.frameID) }

    // The source reports zero for every tick; numbering is the clock's job precisely so that all
    // consumers agree even when the source cannot count.
    ticker.fire(at: 0, target: 0.008)
    ticker.fire(at: 0.008, target: 0.016)
    #expect(seen == [1, 2])
}

@Test @MainActor
func sourceStartsOnFirstObserverAndStopsAfterTheLast() {
    let ticker = ManualTicker()
    let clock = FrameClock(source: ticker)

    let first = clock.subscribe { _ in }
    let second = clock.subscribe { _ in }
    #expect(ticker.startCount == 1)
    #expect(ticker.isRunning)

    clock.unsubscribe(first)
    #expect(ticker.isRunning)

    clock.unsubscribe(second)
    #expect(ticker.isRunning == false)
    #expect(ticker.stopCount == 1)
    #expect(clock.observerCount == 0)
}

@Test @MainActor
func timestampsArePassedThroughUnchanged() {
    let ticker = ManualTicker()
    let clock = FrameClock(source: ticker)
    var last: FrameTick?
    _ = clock.subscribe { last = $0 }

    ticker.fire(at: 12.5, target: 12.508_333)
    #expect(last?.timestamp == 12.5)
    #expect(last?.targetTimestamp == 12.508_333)
    #expect(clock.latest == last)
}

/// Registration order, not hash order. Two charts on one clock touching a shared provider in an
/// order that varies between launches would undercut the identical-work claim the clock exists for.
@Test @MainActor
func observersAreCalledInRegistrationOrder() {
    let ticker = ManualTicker()
    let clock = FrameClock(source: ticker)
    var order: [Int] = []
    var tokens: [FrameClock.Token] = []
    for index in 0..<12 {
        tokens.append(clock.subscribe { _ in order.append(index) })
    }

    ticker.fire(at: 0, target: 0.008)
    #expect(order == Array(0..<12))

    for token in tokens { clock.unsubscribe(token) }
    #expect(clock.observerCount == 0)
}

/// Unsubscribing from inside a callback must take effect for the *next* tick, and must not stop
/// the source while the current fan-out is still running.
@Test @MainActor
func unsubscribingFromInsideACallbackIsSafe() {
    let ticker = ManualTicker()
    let clock = FrameClock(source: ticker)
    var firstCalls = 0
    var secondCalls = 0

    var firstToken: FrameClock.Token?
    firstToken = clock.subscribe { _ in
        firstCalls += 1
        if let token = firstToken { clock.unsubscribe(token) }
    }
    let secondToken = clock.subscribe { _ in secondCalls += 1 }

    ticker.fire(at: 0, target: 0.008)
    ticker.fire(at: 0.008, target: 0.016)

    #expect(firstCalls == 1)
    #expect(secondCalls == 2)
    clock.unsubscribe(secondToken)
}
