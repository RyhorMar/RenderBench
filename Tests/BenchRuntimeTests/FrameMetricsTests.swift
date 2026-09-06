import Testing
@testable import BenchRuntime

/// `pointsDrawn`/`drawCalls` are optional for the same reason `rasterNs`/`gpuNs` are: a backend
/// that cannot report a count must leave it `nil`, and a `0` written in its place would claim a
/// count that was never taken. Nothing downstream computes with either field today, so only a
/// direct check on the value the initialiser stored can tell a coercion from a pass-through.
@Test
func pointsDrawnAndDrawCallsSurviveAsNilRatherThanBeingCoercedToZero() {
    let metrics = FrameMetrics(
        frameID: 1,
        cpuPrepareNs: 100,
        cpuEncodeNs: 200,
        targetTimestamp: 0,
        pointsSubmitted: 800,
        pointsDrawn: nil,
        drawCalls: nil
    )
    #expect(metrics.pointsDrawn == nil)
    #expect(metrics.drawCalls == nil)
}
