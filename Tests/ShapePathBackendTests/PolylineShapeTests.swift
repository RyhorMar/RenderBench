import SwiftUI
import Testing
@testable import ShapePathBackend

/// Counts `.move` elements in a built path — the number of subpaths it holds.
private func subpathCount(_ path: Path) -> Int {
    var moves = 0
    path.forEach { element in
        if case .move = element { moves += 1 }
    }
    return moves
}

@Test
func noBreakProducesOneSubpath() {
    let shape = PolylineShape(
        points: [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 20, y: 10)],
        breaks: []
    )
    #expect(subpathCount(shape.path(in: .zero)) == 1)
}

/// Without this, a mutation that stopped honouring `breaks` would still pass every other test in
/// this target: nothing else here has a gap in it to draw through.
@Test
func aBreakStartsANewSubpathRatherThanConnectingAcrossIt() {
    let shape = PolylineShape(
        points: [
            CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0),
            CGPoint(x: 20, y: 10), CGPoint(x: 30, y: 10),
        ],
        breaks: [2]
    )
    let path = shape.path(in: .zero)
    #expect(subpathCount(path) == 2, "a break must start a new subpath rather than connecting through it")

    // The second subpath's first element must be its own `move`, landing exactly on the point
    // after the break — not a `line` drawn from wherever the first subpath ended.
    var elements: [Path.Element] = []
    path.forEach { elements.append($0) }
    guard elements.count == 4, case .move(let moved) = elements[2] else {
        Issue.record("expected a move at the break")
        return
    }
    #expect(moved == CGPoint(x: 20, y: 10))
}

@Test
func twoConsecutiveBreaksStillProduceOneNewSubpath() {
    // `ShapePathChartRenderer` may insert the same index twice for adjacent breaks; the shape
    // must not fold that into an extra empty subpath.
    let shape = PolylineShape(
        points: [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 10)],
        breaks: [1, 1]
    )
    #expect(subpathCount(shape.path(in: .zero)) == 2)
}
