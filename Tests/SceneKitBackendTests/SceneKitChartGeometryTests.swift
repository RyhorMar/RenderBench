import BenchCore
import BenchRuntime
import Foundation
import SceneKit
import Testing
@testable import SceneKitBackend

/// One `.line` segment's endpoint indices, comparable with `==` for a test's expected value —
/// a plain tuple cannot be, and this exists for no other reason.
private struct IndexPair: Equatable {
    let start: Int32
    let end: Int32
}

/// Decodes an `.line`-primitive element's index buffer back into pairs, assuming the four-byte
/// indices `SceneKitChartGeometry` always builds — the only width it ever passes to
/// `SCNGeometryElement(indices:primitiveType:)`.
private func indexPairs(_ element: SCNGeometryElement) -> [IndexPair] {
    var indices: [Int32] = []
    element.data.withUnsafeBytes { raw in
        indices = Array(raw.bindMemory(to: Int32.self))
    }
    return stride(from: 0, to: indices.count, by: 2).map { IndexPair(start: indices[$0], end: indices[$0 + 1]) }
}

private func frame(plot: PlotRect = PlotRect(x: 0, y: 0, width: 100, height: 100)) -> PreparedFrame {
    PreparedFrame(plotRect: plot)
}

@Test
func canvasSizeAddsBackTheFixedInsets() {
    var subject = frame(plot: PlotRect(x: 52, y: 10, width: 960, height: 736))
    subject.chrome = ChromeLayout.build(plot: subject.plotRect, xTicks: [], yTicks: [], chrome: .light, scale: 1)
    let canvas = SceneKitChartGeometry.canvasSize(for: subject)
    #expect(canvas.width == 1_024)
    #expect(canvas.height == 768)
}

@Test
func positioningTheCameraCentresItOnTheCanvasAtHalfHeightScale() {
    let cameraNode = SceneKitChartGeometry.makeCamera()
    var subject = frame(plot: PlotRect(x: 52, y: 10, width: 960, height: 736))
    subject.chrome = ChromeLayout.build(plot: subject.plotRect, xTicks: [], yTicks: [], chrome: .light, scale: 1)
    SceneKitChartGeometry.positionCamera(cameraNode, for: subject)
    #expect(cameraNode.camera?.orthographicScale == 384)
    #expect(cameraNode.position.x == 512)
    #expect(cameraNode.position.y == 384)
}

@Test
func anUndrawablePlotProducesNoContent() {
    let subject = frame(plot: PlotRect(x: 0, y: 0, width: 0, height: 0))
    let result = SceneKitChartGeometry.buildContent(subject)
    #expect(result.node.childNodes.isEmpty)
    #expect(result.pointsDrawn == 0)
}

/// Without this, a mutation that stopped honouring `isBreak` would still pass every pixel-based
/// test in this target: the reference render already fails those, so a structural difference is
/// the only place left this project's usual "draw through the gap" mistake could hide.
@Test
func aBreakEndsOneElementAndStartsANewOneRatherThanConnectingAcrossIt() throws {
    var subject = frame(plot: PlotRect(x: 0, y: 0, width: 100, height: 100))
    let colour = Palette.colour(forSeries: 0, dark: false)
    subject.series = [
        PreparedSeries(index: 0, colour: colour, points: [
            PlottedPoint(x: 0.0, y: 0.0, isBreak: false),
            PlottedPoint(x: 0.1, y: 0.1, isBreak: false),
            PlottedPoint(x: 0.2, y: 0.2, isBreak: false),
            PlottedPoint(x: 0, y: 0, isBreak: true),
            PlottedPoint(x: 0.6, y: 0.6, isBreak: false),
            PlottedPoint(x: 0.7, y: 0.7, isBreak: false),
        ]),
    ]

    let result = SceneKitChartGeometry.buildContent(subject)
    #expect(result.pointsDrawn == 5, "the break itself must not become a vertex")

    guard let seriesNode = result.node.childNodes.first(where: { $0.geometry != nil }),
          let geometry = seriesNode.geometry else {
        Issue.record("expected a geometry node for the series")
        return
    }
    // `#require`, not `#expect`: the two index reads right below assume exactly two elements, and
    // a mutation that collapses a broken series into one element must fail this test cleanly
    // rather than crash the whole process on an out-of-bounds `elements[1]`.
    try #require(geometry.elements.count == 2, "one run before the break, one after — never one spanning it")

    let firstRun = indexPairs(geometry.elements[0])
    let secondRun = indexPairs(geometry.elements[1])
    #expect(firstRun == [IndexPair(start: 0, end: 1), IndexPair(start: 1, end: 2)])
    // The second run's indices start at 3, the vertex right after the break — not at 2, which
    // would silently draw a segment from the run before the break into the one after it.
    #expect(secondRun == [IndexPair(start: 3, end: 4)])
}

@Test
func aRunOfOnePointBetweenBreaksContributesNoElement() {
    var subject = frame(plot: PlotRect(x: 0, y: 0, width: 100, height: 100))
    let colour = Palette.colour(forSeries: 0, dark: false)
    subject.series = [
        PreparedSeries(index: 0, colour: colour, points: [
            PlottedPoint(x: 0.0, y: 0.0, isBreak: false),
            PlottedPoint(x: 0.1, y: 0.1, isBreak: false),
            PlottedPoint(x: 0, y: 0, isBreak: true),
            PlottedPoint(x: 0.5, y: 0.5, isBreak: false),
            PlottedPoint(x: 0, y: 0, isBreak: true),
            PlottedPoint(x: 0.8, y: 0.8, isBreak: false),
            PlottedPoint(x: 0.9, y: 0.9, isBreak: false),
        ]),
    ]

    let result = SceneKitChartGeometry.buildContent(subject)
    #expect(result.pointsDrawn == 5)

    guard let seriesNode = result.node.childNodes.first(where: { $0.geometry != nil }),
          let geometry = seriesNode.geometry else {
        Issue.record("expected a geometry node for the series")
        return
    }
    #expect(geometry.elements.count == 2, "the isolated single point between two breaks draws nothing")
}

@Test
func chromeLinesEachBecomeTheirOwnTwoVertexElement() throws {
    var subject = frame(plot: PlotRect(x: 52, y: 10, width: 960, height: 736))
    subject.xTicks = [PlottedTick(position: 0.5, label: "t")]
    subject.yTicks = [PlottedTick(position: 0.5, label: "v")]
    subject.chrome = ChromeLayout.build(plot: subject.plotRect, xTicks: subject.xTicks, yTicks: subject.yTicks, chrome: .light, scale: 1)

    let result = SceneKitChartGeometry.buildContent(subject)
    let chromeNodes = result.node.childNodes.filter { $0.geometry != nil }
    #expect(chromeNodes.count == subject.chrome.lines.count)
    for node in chromeNodes {
        // `#require`, not `#expect`: the index read right below assumes exactly one element.
        let geometry = try #require(node.geometry)
        try #require(geometry.elements.count == 1)
        #expect(indexPairs(geometry.elements[0]) == [IndexPair(start: 0, end: 1)])
    }
}
