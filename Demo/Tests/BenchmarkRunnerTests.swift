import BenchRuntime
import CoreGraphics
import Foundation
import Testing
@testable import RenderBenchDemo

/// Storage that keeps the plan in memory, so a whole three-repeat sweep runs without a filesystem.
@MainActor
final class MemoryRunStorage: RunStorage {
    var plan: RunPlan?
    var written: [BenchmarkResult] = []
    var discards = 0

    func loadPlan() -> RunPlan? { plan }
    func save(_ plan: RunPlan) { self.plan = plan }
    func discardPlan() { plan = nil; discards += 1 }
    func write(_ result: BenchmarkResult) -> String? {
        written.append(result)
        return "run.json"
    }
}

@MainActor
private func makeScene(_ ticker: ManualTicker) -> ChartScene {
    let scene = ChartScene(ticker: ticker)
    scene.chartSize = CGSize(width: 400, height: 200)
    return scene
}

/// A machine that satisfies every precondition, as a runner sees it.
private let goodMachine = RunConditions(
    isSimulator: false,
    isDebugBuild: false,
    lowPowerModeEnabled: false,
    thermalState: .nominal,
    batteryLevel: 0.9,
    debuggerAttached: false,
    displayMaximumFramesPerSecond: 120,
    frameRate: FrameRateRequest(displayMaximumFramesPerSecond: 120,
                                optedInToHighFrameRate: true),
    idleTimerDisabled: true
)

/// A mutable cell, so a test can change the machine under a runner that already holds a closure
/// reading it.
@MainActor
private final class Box {
    var value: RunConditions
    init(_ value: RunConditions) { self.value = value }
}

/// Drives a runner to completion, firing frames and cool-down seconds until it stops asking for
/// either. Returns how many relaunches the plan demanded.
@MainActor
private func drive(_ runner: BenchmarkRunner, _ ticker: ManualTicker, limit: Int = 20_000) -> Int {
    var relaunches = 0
    var time = 0.0
    for _ in 0..<limit {
        switch runner.phase {
        case .warmup, .measuring:
            time += 1.0 / 120
            ticker.fire(at: time)
        case .cooling:
            runner.secondElapsed()
        case .awaitingRelaunch:
            relaunches += 1
            runner.resume()
        case .idle, .blocked, .wrote, .abandoned:
            return relaunches
        }
    }
    return relaunches
}

/// The whole sweep: every backend, three repeats, one file.
@MainActor
@Test
func aRunProducesOneFileWithEveryBackendInEveryRepeat() {
    let ticker = ManualTicker()
    let scene = makeScene(ticker)
    let storage = MemoryRunStorage()
    let runner = BenchmarkRunner(scene: scene, storage: storage, conditions: { goodMachine })
    scene.onFrame = { [weak runner] in runner?.frameDrawn() }

    runner.start(backends: ["canvas", "shape-path"], repeats: 3, seed: 7)
    let relaunches = drive(runner, ticker)

    #expect(relaunches == 2, "three repeats need the process restarted twice, not three times")
    guard case .wrote = runner.phase else {
        Issue.record("run ended as \(runner.phase)")
        return
    }
    let result = storage.written.first
    #expect(storage.written.count == 1)
    #expect(result?.cases.count == 6)
    #expect(Set(result?.cases.map(\.repeatIndex) ?? []) == [1, 2, 3])
    #expect(Set(result?.cases.map(\.backend) ?? []) == ["canvas", "shape-path"])
    #expect(storage.discards == 1, "the plan is thrown away once the file exists")
}

/// The warm-up is discarded, not counted.
///
/// This is the assertion the whole warm-up exists for: if the frames that paid for allocation and
/// the first texture upload stayed in the sink, the percentiles would describe the launch.
@MainActor
@Test
func theWarmupFramesAreNotAmongTheMeasuredOnes() {
    let ticker = ManualTicker()
    let scene = makeScene(ticker)
    let storage = MemoryRunStorage()
    let runner = BenchmarkRunner(scene: scene, storage: storage, conditions: { goodMachine })
    scene.onFrame = { [weak runner] in runner?.frameDrawn() }

    var plan = RunPlan.make(
        id: "t", seed: 1, backends: ["canvas"], repeats: 1,
        startedAt: Date(), thermalStateAtStart: .nominal,
        warmupFrames: 40, measuredFrames: 30, cooldownSeconds: 1
    )
    plan.repeatIndex = 1
    storage.plan = plan
    runner.resume()
    _ = drive(runner, ticker)

    let measured = storage.written.first?.cases.first
    #expect(measured?.warmupFrames == 40)
    #expect((measured?.measuredFrames ?? 0) <= 30, "measured \(measured?.measuredFrames ?? -1) of 30")
    #expect((measured?.measuredFrames ?? 0) >= 20)
}

/// A violated precondition stops the run before it starts, and says which one.
@MainActor
@Test
func aViolatedPreconditionRefusesToStartAndNamesItself() {
    let ticker = ManualTicker()
    let scene = makeScene(ticker)
    var hot = goodMachine
    hot.thermalState = .serious
    let runner = BenchmarkRunner(scene: scene, storage: MemoryRunStorage(), conditions: { hot })

    runner.start(backends: ["canvas"], repeats: 1)
    guard case .blocked(let titles) = runner.phase else {
        Issue.record("started anyway: \(runner.phase)")
        return
    }
    #expect(titles == ["Thermal state nominal"])
}

/// Preconditions are read again at the end, and a run that ends violated is not filed.
///
/// A run that begins nominal and ends hot measured two different machines. Checking only at the
/// start would file it as if it had measured one.
@MainActor
@Test
func aRunThatEndsOnAViolationIsNotFiled() {
    let ticker = ManualTicker()
    let scene = makeScene(ticker)
    let storage = MemoryRunStorage()
    let machine = Box(goodMachine)
    let runner = BenchmarkRunner(scene: scene, storage: storage, conditions: { machine.value })
    scene.onFrame = { [weak runner] in runner?.frameDrawn() }

    var plan = RunPlan.make(
        id: "t", seed: 1, backends: ["canvas"], repeats: 1,
        startedAt: Date(), thermalStateAtStart: .nominal,
        warmupFrames: 2, measuredFrames: 20, cooldownSeconds: 1
    )
    plan.repeatIndex = 1
    storage.plan = plan
    runner.resume()
    machine.value.thermalState = .serious
    _ = drive(runner, ticker)

    #expect(storage.written.isEmpty, "a run that ended hot was filed anyway")
    guard case .blocked = runner.phase else {
        Issue.record("ended as \(runner.phase)")
        return
    }
}

/// The order is randomised per repeat and reproducible from the seed.
///
/// Both halves matter. One order used three times lets thermal drift settle onto whichever backend
/// goes last; an order nobody can reproduce makes an ordering effect indistinguishable from a real
/// difference.
@Test
func theOrderIsFreshEachRepeatAndReproducibleFromTheSeed() {
    let backends = ["a", "b", "c", "d", "e", "f", "g", "h", "i"]
    let one = RunPlan.make(id: "1", seed: 42, backends: backends, repeats: 3,
                           startedAt: Date(), thermalStateAtStart: .nominal)
    let again = RunPlan.make(id: "2", seed: 42, backends: backends, repeats: 3,
                             startedAt: Date(), thermalStateAtStart: .nominal)
    let other = RunPlan.make(id: "3", seed: 43, backends: backends, repeats: 3,
                             startedAt: Date(), thermalStateAtStart: .nominal)

    #expect(one.order == again.order, "the same seed gave a different order")
    #expect(one.order != other.order, "a different seed gave the same order")
    #expect(Set(one.order[0]) == Set(backends), "an order lost or invented a backend")
    #expect(one.order[0] != one.order[1] || one.order[1] != one.order[2],
            "all three repeats used one order")
}

/// A repeat interrupted part-way is dropped rather than stitched onto the next process.
@MainActor
@Test
func aHalfFinishedRepeatIsDiscardedOnResume() {
    let ticker = ManualTicker()
    let scene = makeScene(ticker)
    let storage = MemoryRunStorage()
    let runner = BenchmarkRunner(scene: scene, storage: storage, conditions: { goodMachine })
    scene.onFrame = { [weak runner] in runner?.frameDrawn() }

    var plan = RunPlan.make(
        id: "t", seed: 1, backends: ["canvas", "shape-path"], repeats: 1,
        startedAt: Date(), thermalStateAtStart: .nominal,
        warmupFrames: 2, measuredFrames: 20, cooldownSeconds: 1
    )
    plan.repeatIndex = 1
    // A case from the process that died: same repeat, and it must not survive into this one.
    plan.cases = [BenchmarkCase(
        chartKind: .stripChart, backend: "canvas", seriesCount: 8, pointsPerSeries: 10,
        refreshHz: 120, policy: .minMax, warmupFrames: 2, measuredFrames: 20, repeatIndex: 1,
        cpu: FrameStatistics(sampleCount: 20, p50Ns: 1, p95Ns: 2, p99Ns: 3, maxNs: 4),
        gpu: nil, missedDeadlineRatio: nil, pointsSubmitted: 10, pointsDrawn: nil,
        drawCalls: nil, equivalence: .notChecked
    )]
    storage.plan = plan
    runner.resume()
    _ = drive(runner, ticker)

    let cases = storage.written.first?.cases ?? []
    #expect(cases.count == 2, "expected both backends measured in this process, got \(cases.count)")
    #expect(cases.allSatisfy { $0.cpu.p50Ns != 1 }, "a case from the dead process survived")
}

/// The recorded refresh rate is the display's, not whatever the scene last saw between two ticks.
///
/// `ChartScene.observedHz` is one tick pair wide. A backend that cannot keep up reports whichever
/// gap the reader happened to catch — 120 as readily as 11 — and this field says what rate the
/// frames were being asked for. Driven here at 40 frames a second on a machine whose display says
/// 120, so the two cannot be confused with each other.
@MainActor
@Test
func theRecordedRefreshRateIsTheDisplaysNotTheOneJustObserved() {
    let ticker = ManualTicker()
    let scene = makeScene(ticker)
    let storage = MemoryRunStorage()
    let runner = BenchmarkRunner(scene: scene, storage: storage, conditions: { goodMachine })
    scene.onFrame = { [weak runner] in runner?.frameDrawn() }

    var plan = RunPlan.make(
        id: "t", seed: 1, backends: ["canvas"], repeats: 1,
        startedAt: Date(), thermalStateAtStart: .nominal,
        warmupFrames: 2, measuredFrames: 30, cooldownSeconds: 1
    )
    plan.repeatIndex = 1
    storage.plan = plan
    runner.resume()

    var time = 0.0
    for _ in 0..<2_000 {
        switch runner.phase {
        case .warmup, .measuring:
            time += 1.0 / 40
            ticker.fire(at: time)
        case .cooling:
            runner.secondElapsed()
        default:
            break
        }
        if case .wrote = runner.phase { break }
    }

    #expect(Int(scene.observedHz.rounded()) == 40, "the scene saw \(scene.observedHz)")
    #expect(storage.written.first?.cases.first?.refreshHz == 120)
}

/// No case is ever measured while the data window is still filling.
///
/// The pipeline is primed with a whole window at rebuild, so this holds from the first frame —
/// checked rather than assumed, because it was assumed the other way first. A measurement taken on
/// a filling window spends part of its frames drawing a lighter chart than the one it claims to
/// measure, and with a randomised order that would flatter a different backend in every repeat.
@MainActor
@Test
func noCaseIsMeasuredWhileTheWindowIsStillFilling() {
    let ticker = ManualTicker()
    let scene = makeScene(ticker)
    let storage = MemoryRunStorage()
    let runner = BenchmarkRunner(scene: scene, storage: storage, conditions: { goodMachine })
    scene.onFrame = { [weak runner] in runner?.frameDrawn() }

    var plan = RunPlan.make(
        id: "t", seed: 1, backends: ["canvas", "shape-path"], repeats: 1,
        startedAt: Date(), thermalStateAtStart: .nominal,
        warmupFrames: 2, measuredFrames: 20, cooldownSeconds: 1
    )
    plan.repeatIndex = 1
    storage.plan = plan
    runner.resume()

    var time = 0.0
    var everMeasuredAPartialWindow = false
    for _ in 0..<20_000 {
        switch runner.phase {
        case .warmup:
            time += 1.0 / 120
            ticker.fire(at: time)
        case .measuring:
            if !scene.windowIsFull { everMeasuredAPartialWindow = true }
            time += 1.0 / 120
            ticker.fire(at: time)
        case .cooling:
            runner.secondElapsed()
        default:
            break
        }
        if case .wrote = runner.phase { break }
        if case .abandoned = runner.phase { break }
    }

    #expect(everMeasuredAPartialWindow == false)
    #expect(storage.written.first?.cases.count == 2)
}

/// A case interrupted part-way is abandoned, and the repeat it belonged to does not survive.
///
/// The app leaving the foreground is what this is for: a backgrounded app gets no display link, so
/// the case would wait forever at whatever frame it reached, and frames either side of such a gap
/// were drawn by a process that was suspended and rewarmed in between.
@MainActor
@Test
func aCaseInterruptedPartWayIsAbandonedAndItsRepeatDropped() {
    let ticker = ManualTicker()
    let scene = makeScene(ticker)
    let storage = MemoryRunStorage()
    let runner = BenchmarkRunner(scene: scene, storage: storage, conditions: { goodMachine })
    scene.onFrame = { [weak runner] in runner?.frameDrawn() }

    runner.start(backends: ["canvas", "shape-path"], repeats: 1, seed: 3)
    var time = 0.0
    for _ in 0..<40 {
        if case .warmup = runner.phase { time += 1.0 / 120; ticker.fire(at: time) }
        if case .measuring = runner.phase { time += 1.0 / 120; ticker.fire(at: time) }
    }
    runner.interrupted(reason: "the app left the foreground")

    guard case .abandoned(let reason) = runner.phase else {
        Issue.record("kept going as \(runner.phase)")
        return
    }
    #expect(reason == "the app left the foreground")
    #expect(storage.written.isEmpty)

    // What the next process finds: a plan whose partly-measured repeat is dropped rather than
    // stitched onto a fresh one.
    let runnerAgain = BenchmarkRunner(scene: scene, storage: storage, conditions: { goodMachine })
    scene.onFrame = { [weak runnerAgain] in runnerAgain?.frameDrawn() }
    runnerAgain.resume()
    #expect(runnerAgain.plan?.cases.isEmpty == true)
}
