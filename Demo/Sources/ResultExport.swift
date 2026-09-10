import BenchCore
import BenchDownsampling
import BenchHost
import BenchRuntime
import Foundation
import UIKit

/// Writes the current session's metrics to a file the user can retrieve from Files.
///
/// This is not the benchmark runner. It has no warm-up, no repeats, no randomised order and no
/// preconditions, so what it produces is a correctly shaped file rather than a valid measurement —
/// and on a simulator `bench-guard` will refuse it, which is exactly right. It exists so that the
/// format is exercised by real code before the device run depends on it.
@MainActor
enum ResultExport {
    /// Assembles a result from the scene's collected metrics.
    ///
    /// `nil` only when the scene has no statistics yet. A backend that cannot report
    /// `pointsDrawn` or `drawCalls` no longer blocks the export: those two fields carry the
    /// absence into the file, which is what the format is for. Formerly this refused outright,
    /// and eight of the nine backends could never be exported at all. Not zero: a
    /// retained-mode backend that never learns its own draw-call count has no honest value to put
    /// in a field this schema declares non-optional, and filing zero there would claim the
    /// cheapest row in the table for a number nobody measured.
    static func result(from scene: ChartScene) -> BenchmarkResult? {
        guard let cpu = scene.statistics else { return nil }

        let screen = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.screen }
            .first
        UIDevice.current.isBatteryMonitoringEnabled = true
        let battery = UIDevice.current.batteryLevel
        let refreshHz = screen?.maximumFramesPerSecond ?? 60

        let environment = RunEnvironment.current(
            maximumFramesPerSecond: refreshHz,
            batteryLevel: battery >= 0 ? Double(battery) : nil,
            thermalStateAtStart: scene.thermalStateAtStart
        )

        return BenchmarkResult(
            run: RunMetadata(
                id: UUID().uuidString,
                startedAt: scene.startedAt,
                gitSha: BuildInfo.gitSha,
                gitDirty: BuildInfo.gitDirty,
                configuration: isDebugBuild ? .debug : .release,
                swiftVersion: BuildInfo.swiftVersion,
                xcodeVersion: BuildInfo.xcodeVersion
            ),
            env: environment,
            cases: [
                BenchmarkCase(
                    chartKind: .stripChart,
                    backend: type(of: scene.renderer).descriptor.identifier,
                    seriesCount: scene.seriesCount,
                    pointsPerSeries: scene.pointsPerSeries,
                    refreshHz: refreshHz,
                    policy: scene.policy,
                    // Zero, and stated as zero. An interactive session has no warm-up phase, and
                    // recording a number here that the run did not perform would be a lie in the
                    // one field that says whether the timings mean anything.
                    warmupFrames: 0,
                    measuredFrames: cpu.sampleCount,
                    repeatIndex: 1,
                    cpu: cpu,
                    raster: scene.rasterStatistics,
                    gpu: scene.gpuStatistics,
                    missedDeadlineRatio: nil,
                    pointsSubmitted: scene.pointsSubmitted,
                    pointsDrawn: scene.pointsDrawn,
                    drawCalls: scene.drawCalls,
                    equivalence: .notChecked
                )
            ]
        )
    }

    /// Writes the result into the app's Documents directory, which is what the Files app exposes.
    ///
    /// - Returns: the file name, or `nil` when there is nothing to write yet.
    static func write(from scene: ChartScene) -> String? {
        guard let result = result(from: scene) else { return nil }
        let name = "renderbench-\(Int(Date().timeIntervalSince1970)).json"
        guard let documents = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else { return nil }

        do {
            let data = try BenchmarkResult.encoder().encode(result)
            try data.write(to: documents.appendingPathComponent(name))
            return name
        } catch {
            return nil
        }
    }

    /// One measured case, as the runner files it.
    ///
    /// Distinct from ``result(from:)`` above in the two fields that say whether the numbers mean
    /// anything: a real warm-up count and the repeat this case belongs to. `bench-guard` reads
    /// exactly those two to tell a measurement from a button press.
    /// - Parameter refreshHz: The display's rate, passed in rather than read off the scene.
    ///   `ChartScene.observedHz` is instantaneous — one tick pair, no window — so a backend
    ///   sustaining 73 frames a second reports 120 as readily as 11, and this field means "the
    ///   rate the frames were being asked for". The rate actually achieved is a different
    ///   quantity, and this format has no field for it.
    static func measuredCase(from scene: ChartScene, refreshHz: Int, warmupFrames: Int,
                             repeatIndex: Int) -> BenchmarkCase? {
        guard let cpu = scene.statistics else { return nil }
        return BenchmarkCase(
            chartKind: .stripChart,
            backend: type(of: scene.renderer).descriptor.identifier,
            seriesCount: scene.seriesCount,
            pointsPerSeries: scene.pointsPerSeries,
            refreshHz: refreshHz,
            policy: scene.policy,
            warmupFrames: warmupFrames,
            measuredFrames: cpu.sampleCount,
            repeatIndex: repeatIndex,
            cpu: cpu,
            // Four backends of the nine time their own draw pass. Dropping it here made the file
            // say none of them did, which is a stronger claim than omitting the column and a false
            // one — and it is the column the cost of a frame is argued in.
            raster: scene.rasterStatistics,
            gpu: scene.gpuStatistics,
            missedDeadlineRatio: nil,
            pointsSubmitted: scene.pointsSubmitted,
            pointsDrawn: scene.pointsDrawn,
            drawCalls: scene.drawCalls,
            equivalence: .notChecked
        )
    }

    /// A finished plan as one file: one run identity, one environment, every case of every repeat.
    static func result(from plan: RunPlan, endingThermalState: ThermalState) -> BenchmarkResult {
        let screen = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.screen }
            .first
        UIDevice.current.isBatteryMonitoringEnabled = true
        let battery = UIDevice.current.batteryLevel
        return BenchmarkResult(
            run: RunMetadata(
                id: plan.id,
                startedAt: plan.startedAt,
                gitSha: BuildInfo.gitSha,
                gitDirty: BuildInfo.gitDirty,
                configuration: isDebugBuild ? .debug : .release,
                swiftVersion: BuildInfo.swiftVersion,
                xcodeVersion: BuildInfo.xcodeVersion
            ),
            env: RunEnvironment(
                deviceModel: RunEnvironment.hardwareIdentifier(),
                osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                isSimulator: RunEnvironment.isRunningOnSimulator,
                maximumFramesPerSecond: screen?.maximumFramesPerSecond ?? 60,
                thermalStateAtStart: plan.thermalStateAtStart,
                thermalStateAtEnd: endingThermalState,
                lowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled,
                batteryLevel: battery >= 0 ? Double(battery) : nil
            ),
            cases: plan.cases
        )
    }

    private static var isDebugBuild: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
}
