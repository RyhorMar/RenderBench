import BenchCore
import BenchDownsampling
import BenchRuntime
import BenchScales
import BenchTestSupport
import CanvasBackend
import CoreGraphics
import Foundation
import QuartzCore
import Testing
@testable import CoreAnimationBackend

private let window: ClosedRange<Carrier> = 0...10
private let yDomain: ClosedRange<Double> = -1.4...1.4
private let size = (
    width: Double(CoreAnimationRenderTarget.width),
    height: Double(CoreAnimationRenderTarget.height)
)

private func eightCurves() -> ArrayProvider {
    let rate = 1_000.0
    var series: [[Sample]] = []
    var metadata: [SeriesMetadata] = []
    for index in 0..<8 {
        let amplitude = 1.0 - Double(index) * 0.06
        let frequency = 0.25 + Double(index) * 0.02
        let phase = Double(index) * .pi / 5
        series.append((0..<10_000).map { step in
            let time = Double(step) / rate
            return Sample(
                carrier: time,
                value: amplitude * sin(2 * .pi * frequency * time + phase)
            )
        })
        metadata.append(SeriesMetadata(name: "s\(index)", unit: .fraction))
    }
    return ArrayProvider(series, metadata: metadata)
}

/// One prepared frame, shared by both backends. This is the whole basis of the comparison: the
/// windowing, the reduction and the projection are identical by construction, so any difference in
/// the pictures is a difference between the rendering methods and nothing else.
private func prepared(seriesCount: Int = 8) -> PreparedFrame {
    var scratch: [Sample] = []
    return FramePreparation.prepare(
        provider: eightCurves(),
        spec: LineChartSpec(series: Array(0..<seriesCount), policy: .minMax),
        window: window,
        yDomain: yDomain,
        size: size,
        dark: false,
        measuring: ApproximateTextWidth(),
        scratch: &scratch
    )
}

@Test
func twoRendersOfOneFrameAreBitIdentical() {
    let frame = prepared()
    guard let first = CoreAnimationRenderTarget.render(frame),
          let second = CoreAnimationRenderTarget.render(frame)
    else {
        Issue.record("could not create a bitmap context")
        return
    }
    #expect(first == second)
    #expect(ImageDifference.between(reference: first, candidate: second).isBitIdentical)
}

/// The comparison the project exists to make, run for the first time. Two genuinely different
/// rendering paths — immediate `Canvas` drawing and a retained layer tree — draw the same prepared
/// frame, and the difference between them has to clear both bars.
@Test
func theTwoBackendsDrawTheSamePicture() {
    let frame = prepared()
    guard let canvas = OffscreenRenderTarget.render(CanvasChartRenderer.encode(frame)),
          let layers = CoreAnimationRenderTarget.render(frame)
    else {
        Issue.record("could not create a bitmap context")
        return
    }

    let difference = ImageDifference.between(reference: canvas, candidate: layers)
    #expect(
        difference.isEquivalent(),
        """
        beyond tolerance: \(difference.fractionBeyondTolerance), \
        PSNR: \(difference.peakSignalToNoiseRatio) dB, \
        worst channel: \(difference.maximumChannelDelta)
        """
    )
}

/// Both backends must submit and draw the same number of points, or a timing comparison between
/// them is measuring different amounts of work whatever the pictures look like.
@Test
func bothBackendsDrawTheSameNumberOfPoints() {
    let frame = prepared()
    let canvas = CanvasChartRenderer.encode(frame)
    let layer = CoreAnimationChartLayer()
    layer.frame = CGRect(x: 0, y: 0, width: size.width, height: size.height)
    let result = layer.update(with: frame)

    #expect(result.pointsSubmitted == canvas.pointsSubmitted)
    #expect(result.pointsDrawn == canvas.pointsDrawn)
    #expect(result.pointsDrawn > 0)
    #expect(result.shapeLayerCount == 8)
}

/// Counts how often a layer is asked what to animate. When actions are disabled Core Animation
/// does not consult the delegate at all, so the count is the mechanism itself rather than a
/// side effect of it.
private final class ActionProbe: NSObject, CALayerDelegate {
    private(set) var queries = 0
    func action(for layer: CALayer, forKey event: String) -> (any CAAction)? {
        queries += 1
        return NSNull()
    }
}

/// Implicit animation is Core Animation's default, and on a chart it is both wrong and expensive:
/// the reader sees a blend of two instants while the layer keeps both geometries alive.
///
/// - Important: **This test cannot distinguish the two settings.** A detached layer tree — which
///   is every tree in a unit test — never consults its delegate for an action and never creates
///   the animation, so re-enabling actions deliberately leaves both assertions below passing.
///   Verified by mutation, which is how the weakness was found rather than assumed. What it does
///   check is that nothing else in `update(with:)` starts an animation. Covering the disable
///   itself needs a layer attached to a real renderer, which is a UI test on a device: backlog
///   item B11.
@Test
func nothingInAnUpdateStartsAnAnimation() {
    let layer = CoreAnimationChartLayer()
    layer.frame = CGRect(x: 0, y: 0, width: size.width, height: size.height)
    layer.update(with: prepared(seriesCount: 2))

    let probe = ActionProbe()
    for sublayer in layer.sublayers ?? [] { sublayer.delegate = probe }
    layer.update(with: prepared(seriesCount: 2))

    #expect(probe.queries == 0, "the layer was asked for an action \(probe.queries) times")

    var animated = 0
    for sublayer in layer.sublayers ?? [] where (sublayer.animationKeys()?.isEmpty == false) {
        animated += 1
    }
    #expect(animated == 0, "\(animated) sublayers are animating a path change")
}

/// Gaps, which the eight-curve fixture has none of. Without this the backend's break handling is
/// untested: a mutation that drew straight through every gap changed nothing in any other test.
@Test
func aGapBreaksTheLineRatherThanBeingDrawnThrough() {
    var values = (0..<2_000).map { Sample(carrier: Double($0) / 200, value: sin(Double($0) / 40)) }
    for index in 800..<900 { values[index] = Sample(carrier: values[index].carrier, value: .nan) }
    let source = ArrayProvider([values], metadata: [SeriesMetadata(name: "g", unit: .fraction)])

    var scratch: [Sample] = []
    let frame = FramePreparation.prepare(
        provider: source,
        spec: LineChartSpec(series: [0], policy: .minMax),
        window: window,
        yDomain: -1.4...1.4,
        size: size,
        dark: false,
        measuring: ApproximateTextWidth(),
        scratch: &scratch
    )
    #expect(frame.series[0].points.contains { $0.isBreak })

    let layer = CoreAnimationChartLayer()
    layer.frame = CGRect(x: 0, y: 0, width: size.width, height: size.height)
    let result = layer.update(with: frame)

    // Breaks are not geometry: the backend draws fewer points than it was handed, by exactly the
    // number of breaks.
    let breaks = frame.series[0].points.filter(\.isBreak).count
    #expect(breaks > 0)
    #expect(result.pointsDrawn == frame.pointsSubmitted - breaks)

    // And it draws the same picture as the Canvas backend on the same gapped frame.
    guard let canvas = OffscreenRenderTarget.render(CanvasChartRenderer.encode(frame)),
          let layers = CoreAnimationRenderTarget.render(frame)
    else {
        Issue.record("could not create a bitmap context")
        return
    }
    #expect(ImageDifference.between(reference: canvas, candidate: layers).isEquivalent())
}

/// Layers are reused across frames. Recreating them would make every frame pay for allocation and
/// for the tree's re-composition, which measures the allocator rather than the rendering method.
@Test
func layersAreReusedAndNeverShrink() {
    let layer = CoreAnimationChartLayer()
    layer.frame = CGRect(x: 0, y: 0, width: size.width, height: size.height)

    layer.update(with: prepared(seriesCount: 8))
    let afterEight = layer.sublayers?.count ?? 0
    layer.update(with: prepared(seriesCount: 2))
    let afterTwo = layer.sublayers?.count ?? 0
    layer.update(with: prepared(seriesCount: 8))
    let afterEightAgain = layer.sublayers?.count ?? 0

    #expect(afterEight == afterEightAgain)
    #expect(afterTwo == afterEight, "layers were destroyed and rebuilt on a series-count change")
}

@Test
func surplusLayersAreHiddenRatherThanLeftShowingStaleGeometry() {
    let layer = CoreAnimationChartLayer()
    layer.frame = CGRect(x: 0, y: 0, width: size.width, height: size.height)
    layer.update(with: prepared(seriesCount: 8))
    layer.update(with: prepared(seriesCount: 3))

    let shapes = (layer.sublayers ?? []).compactMap { $0 as? CAShapeLayer }
    let visibleWithPath = shapes.filter { !$0.isHidden && $0.path != nil }
    // Three series, plus the grid and the axis layers.
    #expect(visibleWithPath.count == 5)

    // Both halves are asserted separately. Clearing the path alone would already hide the stale
    // geometry, which made a mutation of the `isHidden` line invisible; hiding alone would leave
    // the compositor holding geometry nobody can see.
    let surplus = shapes.filter { $0.path == nil }
    #expect(surplus.isEmpty == false)
    #expect(surplus.allSatisfy { $0.isHidden }, "a surplus layer is still visible")
}

@Test
func aRefusedSeriesIsCarriedThroughRatherThanDropped() {
    let gravity = SeriesUnit(
        symbol: "°API",
        quantity: .dimensionless,
        scale: 1,
        offset: 0,
        isAveragable: false
    )
    var scratch: [Sample] = []
    let samples = (0..<1_000).map { Sample(carrier: Double($0) / 100, value: Double($0 % 40)) }
    let provider = ArrayProvider([samples], metadata: [SeriesMetadata(name: "g", unit: gravity)])
    let frame = FramePreparation.prepare(
        provider: provider,
        spec: LineChartSpec(series: [0], policy: .lttb),
        window: window,
        yDomain: 0...40,
        size: size,
        dark: false,
        measuring: ApproximateTextWidth(),
        scratch: &scratch
    )

    let layer = CoreAnimationChartLayer()
    layer.frame = CGRect(x: 0, y: 0, width: size.width, height: size.height)
    let result = layer.update(with: frame)

    #expect(result.failures.count == 1)
    #expect(result.shapeLayerCount == 0)
    #expect(result.pointsDrawn == 0)
}

@Test
func identifierIsPinned() {
    #expect(CoreAnimationBackend.identifier == "core-animation")
}
