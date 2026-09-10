import BenchRuntime
import Testing
@testable import RenderBenchDemo

/// A machine that satisfies everything, as the starting point every case below mutates by one
/// field. Written out rather than read from the host: the host is a simulator, in a debug build,
/// with a debugger attached, which is three violations before the first assertion.
private let clean = RunConditions(
    isSimulator: false,
    isDebugBuild: false,
    lowPowerModeEnabled: false,
    thermalState: .nominal,
    batteryLevel: 0.8,
    debuggerAttached: false,
    displayMaximumFramesPerSecond: 120,
    frameRate: FrameRateRequest(displayMaximumFramesPerSecond: 120,
                                optedInToHighFrameRate: true),
    idleTimerDisabled: true
)

private func states(_ conditions: RunConditions) -> [PreconditionState] {
    RunPreconditions.list(for: conditions).map(\.state)
}

private func blockingTitles(_ conditions: RunConditions) -> [String] {
    RunButton.blockers(in: RunPreconditions.list(for: conditions)).map(\.title)
}

/// The clean machine blocks nothing, and the two rows nobody can check stay unchecked rather than
/// quietly counting as satisfied.
@Test
func aCleanMachineBlocksNothingAndStillAdmitsWhatItCannotSee() {
    #expect(blockingTitles(clean).isEmpty)
    #expect(states(clean).contains(.notChecked))
}

/// Each of these on its own stops a run, and each stops exactly one row.
@Test
func everyConditionTheProcedureNamesBlocksOnItsOwn() {
    var cases: [(String, RunConditions)] = []
    var simulator = clean; simulator.isSimulator = true
    cases.append(("simulator", simulator))
    var debug = clean; debug.isDebugBuild = true
    cases.append(("debug", debug))
    var lowPower = clean; lowPower.lowPowerModeEnabled = true
    cases.append(("low power", lowPower))
    var hot = clean; hot.thermalState = .fair
    cases.append(("thermal fair", hot))
    var flat = clean; flat.batteryLevel = 0.39
    cases.append(("battery 39 %", flat))
    var traced = clean; traced.debuggerAttached = true
    cases.append(("debugger", traced))
    var capped = clean
    capped.frameRate = FrameRateRequest(displayMaximumFramesPerSecond: 120,
                                        optedInToHighFrameRate: false)
    cases.append(("no opt-in", capped))
    var dims = clean; dims.idleTimerDisabled = false
    cases.append(("auto-lock", dims))

    for (name, conditions) in cases {
        #expect(blockingTitles(conditions).count == 1, "\(name) blocked \(blockingTitles(conditions))")
    }
}

/// Thermal is a hard stop at the first step away from nominal, not at the last.
///
/// `serious` is where `bench-guard` refuses a stored file. If the runner only stopped there too,
/// every `fair` run would be taken, stored, and read as if the clocks had been steady.
@Test
func thermalBlocksAtFairNotOnlyAtSerious() {
    for state in ThermalState.allCases {
        var conditions = clean
        conditions.thermalState = state
        let blocked = blockingTitles(conditions).isEmpty == false
        #expect(blocked == (state != .nominal), "\(state.rawValue)")
    }
}

/// A platform with no battery reading is not a platform with a flat battery.
@Test
func anAbsentBatteryReadingIsUncheckedRatherThanViolated() {
    var noBattery = clean
    noBattery.batteryLevel = nil
    #expect(blockingTitles(noBattery).isEmpty)
    #expect(RunPreconditions.list(for: noBattery).filter { $0.state == .notChecked }.count == 2)
}

/// A 60 Hz device needs no opt-in, and asking for 120 on one is not a violation.
///
/// The rule is "ask for everything this display has", not "run at 120": a phone without ProMotion
/// is not a phone with a broken measurement.
@Test
func aSixtyHertzDisplayIsSatisfiedWithoutTheOptIn() {
    var plain = clean
    plain.displayMaximumFramesPerSecond = 60
    plain.frameRate = FrameRateRequest(displayMaximumFramesPerSecond: 60,
                                       optedInToHighFrameRate: false)
    #expect(blockingTitles(plain).isEmpty)
}

/// The reason under a blocked button names the failures rather than counting them.
@Test
func theReasonNamesEveryBlockingCondition() {
    var bad = clean
    bad.isSimulator = true
    bad.lowPowerModeEnabled = true
    let reason = RunButton.reason(for: RunPreconditions.list(for: bad))
    #expect(reason?.contains("simulator") == true)
    #expect(reason?.contains("low power mode off") == true)
}

/// The frame rate row says what is capping the app, and it is now the only thing that can.
///
/// It used to name two halves — the bundle key and the range on the link. The second stopped being
/// representable when the ticker began taking a request it cannot contradict, so the row names the
/// half that remains.
@Test
func theFrameRateRowNamesTheCap() throws {
    var noKey = clean
    noKey.frameRate = FrameRateRequest(displayMaximumFramesPerSecond: 120,
                                       optedInToHighFrameRate: false)
    let row = try #require(RunPreconditions.list(for: noKey).first { $0.state == .violated })
    #expect(row.detail.contains("opt-in"), "\(row.detail)")
    #expect(row.detail.contains("120"), "\(row.detail)")
}
