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
    /// `nil` when the active backend cannot report `pointsDrawn` or `drawCalls`, not zero: a
    /// retained-mode backend that never learns its own draw-call count has no honest value to put
    /// in a field this schema declares non-optional, and filing zero there would claim the
    /// cheapest row in the table for a number nobody measured.
    static func result(from scene: ChartScene) -> BenchmarkResult? {
        guard let cpu = scene.statistics,
              let pointsDrawn = scene.pointsDrawn,
              let drawCalls = scene.drawCalls else { return nil }

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
                    gpu: scene.gpuStatistics,
                    missedDeadlineRatio: nil,
                    pointsSubmitted: scene.pointsSubmitted,
                    pointsDrawn: pointsDrawn,
                    drawCalls: drawCalls,
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

    private static var isDebugBuild: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
}
