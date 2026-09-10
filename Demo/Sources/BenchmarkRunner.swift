import BenchHost
import BenchRuntime
import Foundation

/// Where a run keeps the plan it is working through and the file it finally writes.
///
/// A protocol so a test can run a whole three-repeat sweep without touching the filesystem, and
/// so the one place that names directories is the application rather than the state machine.
@MainActor
protocol RunStorage {
    func loadPlan() -> RunPlan?
    func save(_ plan: RunPlan)
    func discardPlan()
    /// - Returns: the file name written, or `nil` if it could not be written.
    func write(_ result: BenchmarkResult) -> String?
}

/// Works a ``RunPlan`` through, one case at a time, driven by the frames the scene actually draws.
///
/// Driven by frames rather than by seconds on purpose: a backend managing nine frames a second and
/// one managing a hundred and twenty must contribute the same number of samples to their
/// percentiles, or the slow one is measured with a tenth of the evidence and its p95 is noise.
///
/// The runner refuses to start on a violated precondition and refuses to file a result when one is
/// violated at the end. Both ends, because a run that begins nominal and ends hot measured two
/// different machines and only the pair says so.
@MainActor
@Observable
final class BenchmarkRunner {
    enum Phase: Equatable {
        case idle
        /// Every violated precondition, by title. The button says the same thing; this is what a
        /// test reads.
        case blocked([String])
        case warmup(backend: String, framesLeft: Int)
        case measuring(backend: String, framesLeft: Int)
        case cooling(secondsLeft: Int)
        /// One repeat finished and the next needs a fresh process. The application cannot restart
        /// itself, so this is where it hands the job back.
        case awaitingRelaunch(finished: Int, of: Int)
        case wrote(file: String)
        case abandoned(reason: String)
    }

    private(set) var phase: Phase = .idle
    private(set) var plan: RunPlan?

    private let scene: ChartScene
    private let storage: any RunStorage
    private let conditions: @MainActor () -> RunConditions
    private let now: () -> Date

    init(
        scene: ChartScene,
        storage: any RunStorage,
        conditions: @escaping @MainActor () -> RunConditions = RunConditions.current,
        now: @escaping () -> Date = Date.init
    ) {
        self.scene = scene
        self.storage = storage
        self.conditions = conditions
        self.now = now
    }

    /// A plan left behind by an earlier launch, if there is one to continue.
    var resumable: RunPlan? {
        guard let saved = storage.loadPlan(), !saved.isComplete else { return nil }
        return saved
    }

    /// Begins a fresh run, discarding any plan in progress.
    func start(backends: [String], repeats: Int = 3, seed: UInt64 = UInt64(Date().timeIntervalSince1970)) {
        let current = conditions()
        let blockers = RunButton.blockers(in: RunPreconditions.list(for: current)).map(\.title)
        guard blockers.isEmpty else {
            phase = .blocked(blockers)
            return
        }
        let fresh = RunPlan.make(
            id: UUID().uuidString,
            seed: seed,
            backends: backends,
            repeats: repeats,
            startedAt: now(),
            thermalStateAtStart: current.thermalState
        )
        plan = fresh
        storage.save(fresh)
        beginNextCase()
    }

    /// Continues the plan an earlier launch left behind, in this fresh process.
    func resume() {
        guard var saved = storage.loadPlan(), !saved.isComplete else {
            phase = .idle
            return
        }
        let current = conditions()
        let blockers = RunButton.blockers(in: RunPreconditions.list(for: current)).map(\.title)
        guard blockers.isEmpty else {
            phase = .blocked(blockers)
            return
        }
        // A repeat that was interrupted part-way is dropped rather than stitched onto this one:
        // its cases were measured in a process that is gone, and the point of restarting between
        // repeats is that a repeat is one process.
        saved.cases.removeAll { $0.repeatIndex == saved.repeatIndex }
        plan = saved
        storage.save(saved)
        beginNextCase()
    }

    /// Call once per frame the scene draws.
    func frameDrawn() {
        switch phase {
        case .warmup(let backend, let left):
            if left > 1 {
                phase = .warmup(backend: backend, framesLeft: left - 1)
            } else {
                scene.resetMetrics()
                phase = .measuring(backend: backend, framesLeft: plan?.measuredFrames ?? 0)
            }
        case .measuring(let backend, let left):
            if left > 1 {
                phase = .measuring(backend: backend, framesLeft: left - 1)
            } else {
                finish(backend)
            }
        default:
            break
        }
    }

    /// Call once a second while cooling down.
    func secondElapsed() {
        guard case .cooling(let left) = phase else { return }
        if left > 1 {
            phase = .cooling(secondsLeft: left - 1)
        } else {
            beginNextCase()
        }
    }

    private func finish(_ backend: String) {
        guard var current = plan, let measured = ResultExport.measuredCase(
            from: scene,
            warmupFrames: current.warmupFrames,
            repeatIndex: current.repeatIndex
        ) else {
            phase = .abandoned(reason: "\(backend) produced no statistics")
            return
        }
        current.cases.append(measured)
        plan = current
        storage.save(current)
        scene.stop()
        phase = .cooling(secondsLeft: current.cooldownSeconds)
    }

    private func beginNextCase() {
        guard var current = plan else { return }
        if let next = current.remaining.first {
            guard let entry = Catalogue.renderers.first(where: { $0.id == next }) else {
                phase = .abandoned(reason: "\(next) is not in the catalogue")
                return
            }
            scene.switchRenderer(to: entry)
            scene.start()
            phase = .warmup(backend: next, framesLeft: current.warmupFrames)
            return
        }

        // The repeat is done. Preconditions are read again here, not only at the start.
        let ending = conditions()
        let blockers = RunButton.blockers(in: RunPreconditions.list(for: ending)).map(\.title)
        guard blockers.isEmpty else {
            phase = .blocked(blockers)
            return
        }

        current.repeatIndex += 1
        plan = current
        storage.save(current)
        if current.isComplete {
            fileResult(current, endingThermalState: ending.thermalState)
        } else {
            phase = .awaitingRelaunch(finished: current.repeatIndex - 1, of: current.repeats)
        }
    }

    private func fileResult(_ finished: RunPlan, endingThermalState: ThermalState) {
        let result = ResultExport.result(from: finished, endingThermalState: endingThermalState)
        guard let name = storage.write(result) else {
            phase = .abandoned(reason: "the result could not be written")
            return
        }
        storage.discardPlan()
        phase = .wrote(file: name)
    }
}
