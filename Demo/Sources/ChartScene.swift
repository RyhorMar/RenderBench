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
    private(set) var framesDrawn: UInt64 = 0
    private(set) var droppedFrames: UInt64 = 0
    private(set) var observedHz: Double = 0

    /// Which signal is on screen.
    ///
    /// No `didSet` here: the `@Observable` macro rewrites stored properties into accessors, and a
    /// property observer attached to one does not survive that rewrite — the value changes and the
    /// side effect silently never runs. The view calls ``rebuild()`` on change instead, where the
    /// dependency is visible.
    var scenario: Scenario = .eightSeries
    var policy: DownsamplePolicy = .minMax
    var isRunning = true
    var chartSize: CGSize = .zero

    /// Seconds of history on screen.
    let windowSeconds: Double = 10

    private let metrics = MetricsSink(capacity: 1_200)
    private let slot = FrameSlot()
    private var clock: FrameClock?
    private var ticker: DisplayLinkTicker?
    private var provider = SeriesCollectionProvider(series: [])
    private var scratch: [Sample] = []

    private var signals: [any Signal] = []
    private var sourceRateHz: Double = 100
    private var yDomain: ClosedRange<Double> = -1...1
    private var elapsed: Double = 0
    private var produced: Int = 0
    private var epoch: UInt64 = 1
    private var lastTickTimestamp: Double?

    init() {
        scratch.reserveCapacity(4_096)
        rebuild()
    }

    func start() {
        guard clock == nil else { return }
        let source = DisplayLinkTicker()
        let created = FrameClock(source: source)
        created.subscribe { [weak self] tick in self?.advance(tick) }
        ticker = source
        clock = created
    }

    /// Stops the display link explicitly rather than relying on deallocation.
    ///
    /// On iOS the object graph behind a dismissed screen is released at an unpredictable later
    /// point; until it happens a live display link keeps waking the CPU for a view nobody is
    /// looking at.
    func stop() {
        ticker?.stop()
        ticker = nil
        clock = nil
        lastTickTimestamp = nil
    }

    /// Rebuilds the series set for the current scenario and bumps the epoch, so any frame
    /// prepared under the previous configuration is discarded rather than drawn.
    func rebuild() {
        epoch &+= 1
        elapsed = 0
        produced = 0

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

        let capacity = Int(sourceRateHz * windowSeconds) + 2
        provider = SeriesCollectionProvider(
            series: signals.map { DataSeries(capacity: capacity, metadata: $0.metadata) }
        )
        metrics.removeAll()
        framesDrawn = 0
        droppedFrames = 0
        prime()
    }

    /// Fills the window once so the first frame shows a chart rather than an empty axis.
    private func prime() {
        produce(seconds: windowSeconds)
    }

    private func produce(seconds: Double) {
        let wanted = Int((elapsed + seconds) * sourceRateHz)
        guard wanted > produced else { return }
        var noise = GaussianNoise(seed: SignalSeed.oscillatingReaction &+ UInt64(produced))

        for index in produced..<wanted {
            let time = Double(index) / sourceRateHz
            for (seriesIndex, signal) in signals.enumerated() {
                let clean = signal.value(at: time)
                let value = signal.noiseSigma > 0 ? clean + signal.noiseSigma * noise.next() : clean
                provider.series[seriesIndex].append(Sample(carrier: time, value: value))
            }
        }
        produced = wanted
        elapsed += seconds
    }

    private func advance(_ tick: FrameTick) {
        guard isRunning, chartSize.width > 1 else { return }

        if let previous = lastTickTimestamp {
            let delta = tick.timestamp - previous
            if delta > 0 { observedHz = 1 / delta }
            produce(seconds: delta)
        }
        lastTickTimestamp = tick.timestamp

        let upper = elapsed
        let window = max(0, upper - windowSeconds)...max(0.001, upper)
        slot.publish(
            FrameSnapshot(frameID: tick.frameID, epoch: epoch, window: window, pointCount: produced)
        )
        guard let snapshot = slot.take(epoch: epoch) else { return }

        let spec = LineChartSpec(
            series: Array(signals.indices),
            policy: policy,
            lineWidth: scenario == .carrier ? 1.0 : 1.5
        )
        let built = CanvasChartRenderer.buildFrame(
            provider: provider,
            spec: spec,
            window: snapshot.window,
            yDomain: yDomain,
            size: chartSize,
            dark: false,
            scratch: &scratch
        )

        metrics.record(
            FrameMetrics(
                frameID: snapshot.frameID,
                cpuPrepareNs: built.prepareNs,
                cpuEncodeNs: built.encodeNs,
                targetTimestamp: tick.targetTimestamp,
                pointsSubmitted: built.pointsSubmitted,
                pointsDrawn: built.pointsDrawn,
                drawCalls: built.strokes.count
            )
        )
        frame = built
        framesDrawn &+= 1
        droppedFrames = slot.counters.dropped
        if framesDrawn % 10 == 0 { statistics = metrics.cpuStatistics() }
    }
}
