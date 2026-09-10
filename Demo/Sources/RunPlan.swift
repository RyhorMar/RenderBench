import BenchGenerators
import BenchRuntime
import Foundation

/// The whole sweep, written down before it starts and surviving the process that started it.
///
/// The procedure asks for three repeats with the application restarted between them: a repeat that
/// reuses a warm process measures the process. An application cannot relaunch itself, so the plan
/// is the thing that persists — order, seed, and everything measured so far — and each launch
/// picks up the repeat the last one did not do.
struct RunPlan: Codable, Equatable {
    /// One identifier for all three repeats. They are one run, and a reader comparing repeats has
    /// to be able to tell they came from the same one.
    let id: String
    /// The seed the order came from. Recorded because "randomised" is worthless without it: a
    /// reader who cannot reproduce the order cannot tell an ordering effect from a real one.
    let seed: UInt64
    let startedAt: Date
    let repeats: Int
    /// Backend identifiers, one randomised order per repeat. Fresh per repeat rather than shared:
    /// one order used three times lets thermal drift settle onto the same backend every time.
    let order: [[String]]
    let thermalStateAtStart: ThermalState
    /// Frames discarded before each case is measured, and frames measured after them. Stored on
    /// the plan rather than read from the constants below, so a run that used different numbers
    /// says so instead of being read as if it had used these.
    let warmupFrames: Int
    let measuredFrames: Int
    let cooldownSeconds: Int
    /// 1-based. The repeat this launch is to perform.
    var repeatIndex: Int
    /// Everything finished so far, across every repeat.
    var cases: [BenchmarkCase]

    /// Frames drawn and thrown away before each case is measured.
    ///
    /// The first frames of a case pay for allocation, first-time texture upload and a cold cache.
    /// Including them measures the launch of the backend rather than its drawing.
    static let defaultWarmupFrames = 120
    /// Frames measured per case. Ten seconds at 120 Hz, twenty at 60 — and two minutes on a
    /// backend that manages nine, which is the honest cost of counting frames rather than seconds.
    static let defaultMeasuredFrames = 1_200
    /// Seconds between cases, with the chart stopped.
    static let defaultCooldownSeconds = 20

    static func make(
        id: String,
        seed: UInt64,
        backends: [String],
        repeats: Int,
        startedAt: Date,
        thermalStateAtStart: ThermalState,
        warmupFrames: Int = RunPlan.defaultWarmupFrames,
        measuredFrames: Int = RunPlan.defaultMeasuredFrames,
        cooldownSeconds: Int = RunPlan.defaultCooldownSeconds
    ) -> RunPlan {
        var generator = SplitMix64(seed: seed)
        let orders = (0..<repeats).map { _ in backends.shuffled(using: &generator) }
        return RunPlan(
            id: id,
            seed: seed,
            startedAt: startedAt,
            repeats: repeats,
            order: orders,
            thermalStateAtStart: thermalStateAtStart,
            warmupFrames: warmupFrames,
            measuredFrames: measuredFrames,
            cooldownSeconds: cooldownSeconds,
            repeatIndex: 1,
            cases: []
        )
    }

    /// Backends still to measure in the current repeat, in order.
    var remaining: [String] {
        guard repeatIndex >= 1, repeatIndex <= order.count else { return [] }
        let done = Set(cases.filter { $0.repeatIndex == repeatIndex }.map(\.backend))
        return order[repeatIndex - 1].filter { !done.contains($0) }
    }

    var isComplete: Bool { repeatIndex > repeats }

    /// Where a plan in progress lives between launches. Documents rather than caches: a plan the
    /// system may delete under memory pressure would lose a run half an hour in.
    static func fileURL(in directory: URL) -> URL {
        directory.appendingPathComponent("run-plan.json")
    }
}
