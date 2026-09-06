import BenchCore
import BenchHost
import BenchRuntime
import SwiftUI
import Testing
@testable import CoreAnimationBackend

/// The concrete `View` type an `AnyView` erases, found by reflection.
///
/// `type(of: someAnyView) == AnyView.self` is always true and proves nothing: `AnyView` erases to
/// itself by definition. The actual risk the contract calls out — a conformer whose `surface`
/// sometimes wraps a different concrete type — only shows up in the boxed value `AnyView` hides,
/// which is why this reaches for `Mirror` rather than comparing `AnyView` values directly.
private func erasedViewTypeName(_ view: AnyView) -> String {
    guard let boxed = Mirror(reflecting: view).children.first?.value else { return "AnyView" }
    return String(reflecting: type(of: boxed))
}

private func onePointFrame(pointCount: Int = 100) -> PreparedFrame {
    var frame = PreparedFrame(plotRect: PlotRect(x: 52, y: 10, width: 960, height: 736))
    frame.series = [
        PreparedSeries(
            index: 0,
            colour: Palette.colour(forSeries: 0, dark: false),
            points: (0..<pointCount).map { PlottedPoint(x: Double($0) / Double(pointCount - 1), y: 0.5, isBreak: false) }
        ),
    ]
    frame.chrome = ChromeLayout.build(plot: frame.plotRect, xTicks: [], yTicks: [], chrome: .light, scale: 1)
    return frame
}

@MainActor @Test
func encodeReportsWhatItDrewAndSurfaceIsStable() {
    let renderer = CoreAnimationRenderer()
    let frame = onePointFrame()

    let beforeRevision = renderer.encodedRevision
    let firstSurfaceType = erasedViewTypeName(renderer.surface)
    let report = renderer.encode(frame)

    #expect(report.pointsDrawn == 100)
    #expect(report.drawCalls >= 1)
    #expect(renderer.encodedRevision == beforeRevision + 1)
    #expect(erasedViewTypeName(renderer.surface) == firstSurfaceType)

    renderer.teardown()
    // A torn-down renderer is inert, not crashing.
    let afterTeardown = renderer.encode(frame)
    #expect(afterTeardown.pointsDrawn == 0)
}

/// This backend never observes rasterisation — the render server does that on its own thread,
/// after `encode(_:)` has returned — and `descriptor.reportsRasterTime == false` says so. A
/// non-`nil` reading here would be reporting a number nothing actually measured.
@MainActor @Test
func takeDeferredTimesNeverReportsAnythingItCannotObserve() {
    let renderer = CoreAnimationRenderer()
    _ = renderer.encode(onePointFrame())
    #expect(renderer.takeDeferredTimes() == .none)
}

/// `PreparedFrame.scale` reaches the layer, without a second, independently-sourced scale to
/// disagree with it: the render scale a retained-mode backend needs is already on the frame it is
/// handed, so `encode(_:)` is the only place it should come from.
@MainActor @Test
func encodeAppliesTheFramesScaleToTheLayer() {
    let renderer = CoreAnimationRenderer()
    var frame = onePointFrame()
    frame.scale = 3
    _ = renderer.encode(frame)

    #expect(renderer.layer.renderScale == 3)
}
