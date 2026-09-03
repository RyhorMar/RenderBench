import BenchCore
import BenchDownsampling
import BenchGenerators
import BenchRuntime
import CanvasBackend
import Foundation
import SwiftUI

/// What the demo is showing.
enum Scenario: String, CaseIterable, Identifiable {
    /// Eight phase-shifted reaction curves — the well-behaved case.
    case eightSeries = "8 series"
    /// A single 400 Hz carrier, sampled far above what a pixel column can resolve.
    case carrier = "400 Hz carrier"

    var id: String { rawValue }
}

/// Owns the data, the clock and the metrics for one screen.
///
/// One scene, one clock. Every chart drawn from this object sees the same frame number, so two of
/// them side by side cannot drift apart — which is the whole reason the clock is not a property of
/// a view.
@MainActor
@Observable
final class ChartScene {
    private(set) var frame = CanvasFrame()
    private(set) var statistics: FrameStatistics?
    /// Percentiles of the draw pass itself, separate from preparation. `nil` until a draw has
    /// reported one.
    private(set) var rasterStatistics: FrameStatistics?
    private(set) var framesDrawn: UInt64 = 0
    private(set) var droppedFrames: UInt64 = 0
    private(set) var observedHz: Double = 0

    /// When the current run began, and the thermal state then. Both come from the pipeline, which
    /// records them at the run's start rather than at the application's launch.
    var startedAt: Date { pipeline.runStartedAt }
    var thermalStateAtStart: ThermalState { pipeline.thermalStateAtStart }

    /// Series currently on screen.
    var seriesCount: Int { streams.count }

    /// Samples actually held per series right now.
    ///
    /// The count the ring holds, not the capacity it was built with. Before the window has filled
    /// those differ, and a results file that reported the capacity would overstate the load the
    /// measurement ran at.
    var pointsPerSeries: Int { provider.series.first?.count ?? 0 }

    /// Which signal is on screen.
    ///
    /// No `didSet` here: the `@Observable` macro rewrites stored properties into accessors, and a
    /// property observer attached to one does not survive that rewrite — the value changes and the
    /// side effect silently never runs. The view calls ``rebuild()`` on change instead, where the
    /// dependency is visible.
    var scenario: Scenario = .eightSeries

    /// Which colour set the chart is drawn in. Written by the view from the environment, so the
    /// dark palette is reachable instead of being a set of constants nothing selects.
    var isDark = false
    /// How series are reduced. Changing it bumps the epoch: a snapshot prepared under the
    /// previous policy describes a different picture, and drawing it produces one frame of the old
    /// reduction inside the new one.
    var policy: DownsamplePolicy = .minMax {
        didSet { if policy != oldValue { pipeline.invalidateConfiguration() } }
    }
    var isRunning = true
    var chartSize: CGSize = .zero

    /// Seconds of history on screen.
    let windowSeconds: Double = 10

    private let metrics = MetricsSink(capacity: 1_200)
    /// Carries the draw pass's own time out of the Canvas closure. Read on the next tick, one
    /// frame late — which is stated rather than hidden, and is the only way an immediate-mode
    /// backend's rasterisation can be timed at all.
    let rasterTime = RasterTimeRecorder()
    private var pipeline = FramePipeline(windowSeconds: 10, sampleRateHz: 100)
    private var clock: FrameClock?
    private var ticker: DisplayLinkTicker?
    private var subscription: FrameClock.Token?
    private var provider = SeriesCollectionProvider(series: [])
    private var scratch: [Sample] = []

    private var streams: [SignalStream] = []
    private var sourceRateHz: Double = 100
    private var yDomain: ClosedRange<Double> = -1...1
    private var lastTickTimestamp: Double?

    init() {
        scratch.reserveCapacity(4_096)
        rebuild()
    }

    func start() {
        guard clock == nil else { return }
        let source = DisplayLinkTicker()
        let created = FrameClock(source: source)
        subscription = created.subscribe { [weak self] tick in self?.advance(tick) }
        ticker = source
        clock = created
    }

    /// Stops the display link explicitly rather than relying on deallocation.
    ///
    /// On iOS the object graph behind a dismissed screen is released at an unpredictable later
    /// point; until it happens a live display link keeps waking the CPU for a view nobody is
    /// looking at.
    func stop() {
        // Through the clock, not around it. Stopping the ticker directly left the clock believing
        // it was running with a dead source, so a later `subscribe` on the same instance would
        // register an observer that never fired.
        if let subscription { clock?.unsubscribe(subscription) }
        subscription = nil
        ticker = nil
        clock = nil
        lastTickTimestamp = nil
    }

    /// Rebuilds the series set for the current scenario and bumps the epoch, so any frame
    /// prepared under the previous configuration is discarded rather than drawn.
    func rebuild() {
        let signals: [any Signal]
        switch scenario {
        case .eightSeries:
            sourceRateHz = 100
            yDomain = -1.4...1.4
            signals = (0..<8).map { index in
                OscillatingReaction(
                    amplitude: 1.0 - Double(index) * 0.06,
                    frequency: 0.25 + Double(index) * 0.02,
                    phase: Double(index) * .pi / 5,
                    noiseSigma: 0.01
                )
            }
        case .carrier:
            sourceRateHz = 5_000
            yDomain = -1.4...1.4
            signals = [ModulatedCarrier()]
        }

        // One stream per series, each with its own seed. Sharing a generator across series would
        // correlate their noise; re-creating one per frame would make it depend on frame timing.
        streams = signals.enumerated().map { index, signal in
            SignalStream(
                signal: signal,
                sampleRateHz: sourceRateHz,
                seed: SignalSeed.oscillatingReaction &+ UInt64(index)
            )
        }

        let capacity = Int(sourceRateHz * windowSeconds) + 2
        provider = SeriesCollectionProvider(
            series: signals.map { DataSeries(capacity: capacity, metadata: $0.metadata) }
        )
        metrics.removeAll()
        framesDrawn = 0
        droppedFrames = 0

        pipeline = FramePipeline(windowSeconds: windowSeconds, sampleRateHz: sourceRateHz)
        pipeline.beginRun()
        produce(upTo: pipeline.prime())
    }

    /// Advances every stream to `count` samples. The count comes from the pipeline, which banks
    /// time; a stream that is already there produces nothing.
    private func produce(upTo count: Int) {
        for index in streams.indices {
            streams[index].advance(to: count) { sample in
                provider.series[index].append(sample)
            }
        }
    }

    /// Samples produced so far, across all series.
    private var producedCount: Int { streams.first?.producedCount ?? 0 }

    private func advance(_ tick: FrameTick) {
        guard isRunning, chartSize.width > 1 else { return }

        if let previous = lastTickTimestamp {
            let delta = tick.timestamp - previous
            if delta > 0 { observedHz = 1 / delta }
        }
        lastTickTimestamp = tick.timestamp

        guard let plan = pipeline.advance(tick: tick) else { return }
        produce(upTo: plan.samplesDue)
        let snapshot = plan.snapshot

        let spec = LineChartSpec(
            series: Array(streams.indices),
            policy: policy,
            lineWidth: scenario == .carrier ? 1.0 : 1.5
        )
        let built = CanvasChartRenderer.buildFrame(
            provider: provider,
            spec: spec,
            window: plan.window,
            yDomain: yDomain,
            size: chartSize,
            dark: isDark,
            scratch: &scratch
        )

        metrics.record(
            FrameMetrics(
                frameID: snapshot.frameID,
                cpuPrepareNs: built.prepareNs,
                cpuEncodeNs: built.encodeNs,
                rasterNs: rasterTime.take(),
                targetTimestamp: tick.targetTimestamp,
                pointsSubmitted: built.pointsSubmitted,
                pointsDrawn: built.pointsDrawn,
                drawCalls: built.strokes.count
            )
        )
        frame = built
        framesDrawn &+= 1
        droppedFrames = pipeline.counters.dropped
        if framesDrawn % 10 == 0 {
            statistics = metrics.cpuStatistics()
            rasterStatistics = metrics.rasterStatistics()
        }
    }
}
