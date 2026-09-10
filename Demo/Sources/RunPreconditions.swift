import BenchRuntime
import Foundation

/// The conditions a measurement depends on, as the rows a screen shows.
///
/// Pure: a value in, rows out. That is what lets every combination be tested on a host that is
/// none of the things being asked about — and the rules here are the ones the benchmark procedure
/// states, so a rule that changes there and not here is a disagreement a test can find.
///
/// Enforced at this end and at the other: the runner refuses to start on a violation, and
/// `bench-guard` refuses to store a file whose environment says one held. A procedure enforced at
/// one end only is enforced nowhere.
enum RunPreconditions {
    /// Battery below this fraction is a hard stop: the system starts making its own decisions
    /// about clocks long before the battery is empty, and they are not decisions this benchmark
    /// gets to see.
    static let batteryFloor = 0.4

    static func list(for conditions: RunConditions) -> [Precondition] {
        [
            device(conditions),
            configuration(conditions),
            lowPowerMode(conditions),
            thermal(conditions),
            battery(conditions),
            debugger(conditions),
            frameRate(conditions),
            autoLock(conditions),
            unobservable,
        ]
    }

    private static func device(_ c: RunConditions) -> Precondition {
        Precondition(
            title: "A device, not a simulator",
            detail: c.isSimulator
                ? "a simulator translates Metal, has no thermal envelope and is not this display"
                : "measured on the hardware the numbers claim",
            state: c.isSimulator ? .violated : .held
        )
    }

    private static func configuration(_ c: RunConditions) -> Precondition {
        Precondition(
            title: "Release configuration",
            detail: c.isDebugBuild
                ? "a debug build measures the compiler's bookkeeping"
                : "optimised, the way the code would ship",
            state: c.isDebugBuild ? .violated : .held
        )
    }

    private static func lowPowerMode(_ c: RunConditions) -> Precondition {
        Precondition(
            title: "Low Power Mode off",
            detail: c.lowPowerModeEnabled
                ? "the system is capping clocks and frame rate for reasons of its own"
                : "the system is not throttling on the user's behalf",
            state: c.lowPowerModeEnabled ? .violated : .held
        )
    }

    private static func thermal(_ c: RunConditions) -> Precondition {
        Precondition(
            title: "Thermal state nominal",
            detail: c.thermalState == .nominal
                ? "nominal now; read again at the end, and both go in the file"
                : "\(c.thermalState.rawValue) — a throttled run measures the heat, not the code",
            state: c.thermalState == .nominal ? .held : .violated
        )
    }

    private static func battery(_ c: RunConditions) -> Precondition {
        guard let level = c.batteryLevel else {
            return Precondition(
                title: "Battery at or above \(Int(batteryFloor * 100)) %",
                detail: "this platform reports no battery level, so nobody checked",
                state: .notChecked
            )
        }
        return Precondition(
            title: "Battery at or above \(Int(batteryFloor * 100)) %",
            detail: "\(Int((level * 100).rounded())) %",
            state: level >= batteryFloor ? .held : .violated
        )
    }

    private static func debugger(_ c: RunConditions) -> Precondition {
        Precondition(
            title: "Debugger detached",
            detail: c.debuggerAttached
                ? "a traced process pays for the tracing in every frame"
                : "nothing is tracing this process",
            state: c.debuggerAttached ? .violated : .held
        )
    }

    /// The one this project learned by measuring: the app ran at half the display's rate for its
    /// whole life while every property it asked reported 120.
    private static func frameRate(_ c: RunConditions) -> Precondition {
        let ceiling = Int(c.frameRate.range.maximum)
        return Precondition(
            title: "Asking the display for everything it has",
            detail: c.frameRate.optInMissing
                ? "\(c.displayMaximumFramesPerSecond) Hz display, but the bundle opt-in is absent, so \(ceiling) is the cap"
                : "\(c.displayMaximumFramesPerSecond) Hz display, and the display link asks for \(ceiling)",
            state: c.frameRate.optInMissing ? .violated : .held
        )
    }

    private static func autoLock(_ c: RunConditions) -> Precondition {
        Precondition(
            title: "Auto-lock disabled",
            detail: c.idleTimerDisabled
                ? "the idle timer is off for the duration of the run"
                : "the screen may dim or lock partway through, and a dimmed run is a different run",
            state: c.idleTimerDisabled ? .held : .violated
        )
    }

    /// Named rather than dropped. The procedure asks for these and the app cannot see either one:
    /// there is no API for aeroplane mode, and "brightness held fixed" is a fact about the minutes
    /// around the run rather than about a value that can be read at one instant.
    private static let unobservable = Precondition(
        title: "Aeroplane mode on, brightness fixed",
        detail: "the app cannot see either — check them yourself, this row will never say more",
        state: .notChecked
    )
}
