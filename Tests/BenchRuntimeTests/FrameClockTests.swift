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
    clock.subscribe { left.append($0.frameID) }
    clock.subscribe { right.append($0.frameID) }

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
    clock.subscribe { seen.append($0.frameID) }

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
    clock.subscribe { last = $0 }

    ticker.fire(at: 12.5, target: 12.508_333)
    #expect(last?.timestamp == 12.5)
    #expect(last?.targetTimestamp == 12.508_333)
    #expect(clock.latest == last)
}
