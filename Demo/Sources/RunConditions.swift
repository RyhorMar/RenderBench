import BenchRuntime
import Darwin
import Foundation
import QuartzCore
import UIKit

/// What the machine says about itself right now, as plain values.
///
/// Split from the rules that judge them so the rules can be tested without a device: every
/// combination that decides whether a run may start is a value here, and ``RunPreconditions``
/// turns a value into rows. Nothing in this type decides anything.
struct RunConditions: Equatable {
    var isSimulator: Bool
    var isDebugBuild: Bool
    var lowPowerModeEnabled: Bool
    var thermalState: ThermalState
    /// Fraction in `0...1`, or `nil` where the platform does not report one. `nil` is not zero:
    /// a device without a battery reading is not a device with an empty battery.
    var batteryLevel: Double?
    var debuggerAttached: Bool
    /// What the display can do, from `UIScreen.maximumFramesPerSecond`.
    var displayMaximumFramesPerSecond: Int
    /// Whether the high frame rate opt-in is in the bundle, under the name the system reads.
    var highFrameRateOptIn: Bool
    /// The maximum the display link is configured to ask for.
    var requestedMaximumFramesPerSecond: Double
    var idleTimerDisabled: Bool

    @MainActor
    static func current() -> RunConditions {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let level = UIDevice.current.batteryLevel
        let screen = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.screen }
            .first
        let key = Bundle.main.object(forInfoDictionaryKey: "CADisableMinimumFrameDurationOnPhone")
        return RunConditions(
            isSimulator: RunEnvironment.isRunningOnSimulator,
            isDebugBuild: isDebugBuild,
            lowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled,
            thermalState: ThermalState(ProcessInfo.processInfo.thermalState),
            batteryLevel: level >= 0 ? Double(level) : nil,
            debuggerAttached: isDebuggerAttached(),
            displayMaximumFramesPerSecond: screen?.maximumFramesPerSecond ?? 60,
            highFrameRateOptIn: (key as? Bool) == true,
            requestedMaximumFramesPerSecond: Double(DisplayLinkTicker.displayMaximum.maximum),
            idleTimerDisabled: UIApplication.shared.isIdleTimerDisabled
        )
    }

    private static var isDebugBuild: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    /// Whether this process is being traced.
    ///
    /// Apple's own answer to the question (Technical Q&A QA1361): ask the kernel for this
    /// process's `kinfo_proc` and read `P_TRACED`. There is no API for it, and the alternatives —
    /// a `DEBUG` flag, or whether a debugger was attached at launch — answer a different question:
    /// a debugger attached after launch still stops the process on a breakpoint and still charges
    /// its overhead to every frame measured after that.
    private static func isDebuggerAttached() -> Bool {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        let result = sysctl(&name, u_int(name.count), &info, &size, nil, 0)
        guard result == 0 else { return false }
        return (info.kp_proc.p_flag & P_TRACED) != 0
    }
}
