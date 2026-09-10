import BenchCore
import BenchDownsampling
import BenchGenerators
import BenchHost
import BenchRuntime
import BenchScales
import Foundation
import SwiftUI

#if os(iOS)
import UIKit
#endif

/// What the demo is showing.
enum Scenario: String, CaseIterable, Identifiable {
    /// Eight phase-shifted reaction curves — the well-behaved case.
    case eightSeries = "8 series"
    /// A single 400 Hz carrier, sampled far above what a pixel column can resolve.
    case carrier = "400 Hz carrier"

    var id: String { rawValue }
}

/// Owns the data, the clock and the active backend for one screen.
///
/// One scene, one clock. Every chart drawn from this object sees the same frame number, so two of
/// them side by side cannot drift apart — which is the whole reason the clock is not a property of
/// a view. The backend is the one part of this object a screen can swap out from under it:
/// ``switchRenderer(to:)`` replaces ``renderer`` alone, so the data feeding it never restarts.
@MainActor
@Observable
final class ChartScene {
    private(set) var renderer: any ChartRenderer
    private(set) var statistics: FrameStatistics?
    /// Percentiles of the draw pass itself, separate from preparation. `nil` until a draw has
    /// reported one, or forever on a backend whose descriptor says it cannot report raster time.
    private(set) var rasterStatistics: FrameStatistics?
    /// Percentiles of GPU execution. `nil` on every backend but the one whose descriptor says it
    /// reads GPU timestamps.
    private(set) var gpuStatistics: FrameStatistics?
    private(set) var framesDrawn: UInt64 = 0
    private(set) var droppedFrames: UInt64 = 0
    /// Frames per second over the last second, counted. `nil` while the scene has drawn fewer
    /// than two frames inside that window — including after it stopped, where a held-over number
    /// would describe a scene that is no longer drawing.
    private(set) var observedHz: Double?

    /// Samples handed to the active backend after downsampling, for the most recent frame.
    private(set) var pointsSubmitted: Int = 0
    /// Samples the active backend actually drew for the most recent frame. `nil` means this
    /// backend cannot say, not that it drew none.
    private(set) var pointsDrawn: Int?
    /// Draw calls the active backend issued for the most recent frame. `nil` means this backend
    /// cannot say.
    private(set) var drawCalls: Int?
    /// Series the most recent frame's preparation refused, with the reason.
    private(set) var failures: [SeriesFailure] = []

    /// Which backend is currently drawing.
    var rendererID: String { type(of: renderer).descriptor.identifier }

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

    /// Whether the visible window holds as many samples as it ever will.
    ///
    /// True from the first frame, because ``rebuild()`` primes the pipeline with a whole window
    /// rather than letting the ring fill over ten seconds. It is worth being able to ask: a
    /// measurement taken while the window was still filling would spend part of its frames drawing
    /// a lighter chart than the one it claims to measure, and with a randomised backend order that
    /// would flatter a different backend in every repeat. Nothing but a test asks — the invariant
    /// is what the answer is for.
    var windowIsFull: Bool { pointsPerSeries >= Int(sourceRateHz * windowSeconds) }

    /// Identifies the current data source without exposing it. `SeriesCollectionProvider` is a
    /// value type, so two instances with equal contents would compare equal — of no use to a test
    /// that must tell "the same source" apart from "a new one that happens to look the same".
    /// `switchRenderer(to:)` never touches this; only `rebuild()` does.
    internal var providerIdentity: ObjectIdentifier { ObjectIdentifier(sourceTag) }

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
    private var pipeline = FramePipeline(windowSeconds: 10, sampleRateHz: 100)
    private let ticker: any DisplayTicking
    private var clock: FrameClock?
    private var subscription: FrameClock.Token?
    private var provider = SeriesCollectionProvider(series: [])
    private var scratch: [Sample] = []
    /// Reference tag standing in for the data source's identity. See ``providerIdentity``.
    private var sourceTag = SourceTag()

    private var streams: [SignalStream] = []
    private var sourceRateHz: Double = 100
    private var yDomain: ClosedRange<Double> = -1...1
    private var meter = FrameRateMeter()

    /// - Parameters:
    ///   - renderer: The backend to start with. Defaults to the catalogue's first entry so a
    ///     caller that does not care which backend starts still gets one that exists.
    ///   - ticker: Source of display ticks. A test substitutes a manually driven one; every other
    ///     caller takes the default, which drives frames from the real display link.
    /// The display's rate as UIKit reports it, or 120 when no window scene exists yet.
    ///
    /// The fallback is deliberately the high one. A request above what the display can do is
    /// clamped by the system — measured on an iPhone 16 Pro, 10 September 2026: asking for 240
    /// produced 119.98 Hz — while a request below it is not recovered by anything. Guessing high
    /// costs nothing; guessing low is the defect this whole arrangement exists to prevent.
    static func displayMaximumFramesPerSecond() -> Int {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.screen.maximumFramesPerSecond }
            .first ?? 120
    }

    init(
        renderer: any ChartRenderer = Catalogue.renderers[0].make(),
        ticker: any DisplayTicking = DisplayLinkTicker(
            request: .current(
                displayMaximumFramesPerSecond: ChartScene.displayMaximumFramesPerSecond()
            )
        )
    ) {
        self.renderer = renderer
        self.ticker = ticker
        scratch.reserveCapacity(4_096)
        rebuild()
    }

    func start() {
        guard clock == nil else { return }
        let created = FrameClock(source: ticker)
        subscription = created.subscribe { [weak self] tick in self?.advance(tick) }
        clock = created
        renderer.resume()
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
        clock = nil
        meter = FrameRateMeter()
        observedHz = nil
        renderer.suspend()
    }

    /// Called once for every frame this scene actually draws.
    ///
    /// The benchmark runner counts frames rather than seconds, and this is where it counts them:
    /// a backend managing nine frames a second and one managing a hundred and twenty have to
    /// contribute the same number of samples, or the slow one's percentiles are built from a tenth
    /// of the evidence.
    var onFrame: (() -> Void)?

    /// Throws away everything measured so far without touching the backend or the data.
    ///
    /// This is the end of a warm-up: the frames that paid for allocation and the first texture
    /// upload are discarded, and the percentiles that follow describe the drawing. Distinct from
    /// ``switchRenderer(to:)``, which also clears the metrics but does so because they described a
    /// backend that is no longer here.
    func resetMetrics() {
        metrics.removeAll()
        statistics = nil
        rasterStatistics = nil
        gpuStatistics = nil
    }

    /// Replaces the active backend without touching the data feeding it.
    ///
    /// The provider, the pipeline and the accumulated series survive: only the renderer — and the
    /// metrics describing its frames, which describe the outgoing backend and not the data — are
    /// torn down and reset.
    func switchRenderer(to entry: RendererEntry) {
        renderer.teardown()
        renderer = entry.make()
        metrics.removeAll()
        statistics = nil
        rasterStatistics = nil
        gpuStatistics = nil
        pointsSubmitted = 0
        pointsDrawn = nil
        drawCalls = nil
        failures = []
        framesDrawn = 0
        pipeline.invalidateConfiguration()
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
        sourceTag = SourceTag()
        metrics.removeAll()
        statistics = nil
        rasterStatistics = nil
        gpuStatistics = nil
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

    /// The device's own render scale, e.g. `3` on a 3x display.
    ///
    /// `UIScreen` does not exist on macOS, where `swift test` runs; a scene built there never
    /// draws, so the fallback value is never asked to be correct, only to compile. Read through
    /// the foreground window's scene rather than `UIScreen.main`, which iOS 26 deprecates.
    private var displayScale: Double {
        #if os(iOS)
        let screen = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.screen }
            .first
        return Double(screen?.scale ?? 1)
        #else
        return 1
        #endif
    }

    private func advance(_ tick: FrameTick) {
        guard isRunning, chartSize.width > 1 else { return }

        meter.record(timestamp: tick.timestamp)
        observedHz = meter.rate

        guard let plan = pipeline.advance(tick: tick) else { return }
        produce(upTo: plan.samplesDue)
        let snapshot = plan.snapshot

        // The one backend whose method is the reduction itself must receive every windowed point,
        // unreduced: `FramePreparation.prepare` honours `.none` by skipping reduction entirely,
        // so `encode(_:)` gets the whole window to reduce on the GPU rather than a picture
        // `BenchDownsampling` has already decided.
        let spec = LineChartSpec(
            series: Array(streams.indices),
            policy: type(of: renderer).descriptor.reducesOnGPU ? .none : policy,
            lineWidth: scenario == .carrier ? 1.0 : 1.5
        )
        let prepared = FramePreparation.prepare(
            provider: provider,
            spec: spec,
            window: plan.window,
            yDomain: yDomain,
            size: (width: Double(chartSize.width), height: Double(chartSize.height)),
            chrome: AppChrome.chart(dark: isDark),
            scale: displayScale,
            dark: isDark,
            measuring: ApproximateTextWidth(),
            scratch: &scratch
        )
        let report = renderer.encode(prepared)
        let deferred = renderer.takeDeferredTimes()

        metrics.record(
            FrameMetrics(
                frameID: snapshot.frameID,
                cpuPrepareNs: prepared.prepareNs,
                cpuEncodeNs: report.encodeNs,
                rasterNs: deferred.raster?.nanoseconds,
                gpuNs: deferred.gpu?.nanoseconds,
                presentedTime: deferred.presentedTime,
                targetTimestamp: tick.targetTimestamp,
                pointsSubmitted: prepared.pointsSubmitted,
                pointsDrawn: report.pointsDrawn,
                drawCalls: report.drawCalls
            )
        )
        pointsSubmitted = prepared.pointsSubmitted
        pointsDrawn = report.pointsDrawn
        drawCalls = report.drawCalls
        failures = prepared.failures
        framesDrawn &+= 1
        droppedFrames = pipeline.counters.dropped
        onFrame?()
        if framesDrawn % 10 == 0 {
            statistics = metrics.cpuStatistics()
            rasterStatistics = metrics.rasterStatistics()
            gpuStatistics = metrics.gpuStatistics()
        }
    }
}

/// A reference type whose only job is to have an identity `ObjectIdentifier` can read.
///
/// `ChartScene`'s data source is built from value types throughout — `SeriesCollectionProvider`,
/// `[SignalStream]` — so nothing in it has an identity a test could compare across a
/// `switchRenderer(to:)` call. This tag is created alongside the source in `rebuild()` and nowhere
/// else, purely to give `providerIdentity` something to report.
private final class SourceTag {}
