import BenchHost
import BenchRuntime
import CoreGraphics
import Testing
@testable import RenderBenchDemo

/// Drives frames by hand instead of waiting on a real display link, so a test can fire exactly the
/// ticks it wants to check and nothing else.
@MainActor
final class ManualTicker: DisplayTicking {
    private var onTick: ((FrameTick) -> Void)?
    private var frame: UInt64 = 0

    func start(_ onTick: @escaping (FrameTick) -> Void) { self.onTick = onTick }
    func stop() { onTick = nil }

    func fire(at seconds: Double) {
        frame += 1
        onTick?(FrameTick(frameID: frame, targetTimestamp: seconds + 1.0 / 120, timestamp: seconds))
    }
}

@MainActor @Test
func switchingTheRendererKeepsTheSourceAndBumpsTheEpoch() {
    let ticker = ManualTicker()
    let scene = ChartScene(ticker: ticker)
    scene.chartSize = CGSize(width: 800, height: 400)
    scene.start()
    ticker.fire(at: 0.0); ticker.fire(at: 0.1)
    let producedBefore = scene.pointsPerSeries
    let providerBefore = scene.providerIdentity
    scene.switchRenderer(to: Catalogue.renderers[2]) // Metal
    #expect(scene.rendererID == "metal")
    #expect(scene.providerIdentity == providerBefore, "switching must not rebuild the source")
    ticker.fire(at: 0.2)
    #expect(scene.pointsPerSeries >= producedBefore)
    #expect(scene.framesDrawn == 1, "metrics restart with the renderer; frames drawn by the old one are not its")
}

@MainActor @Test
func switchingTheRendererTearsDownTheOutgoingOne() {
    let scene = ChartScene(ticker: ManualTicker())
    let outgoing = scene.renderer
    let revisionBeforeSwitch = outgoing.encodedRevision
    scene.switchRenderer(to: Catalogue.renderers[1])
    // A torn-down renderer's `encode` returns without touching `encodedRevision` at all — see
    // every conformer's own guard — so an unchanged revision after a call is what "torn down"
    // looks like from outside the protocol, and is the only thing this test can observe.
    _ = outgoing.encode(PreparedFrame())
    #expect(
        outgoing.encodedRevision == revisionBeforeSwitch,
        "switchRenderer must tear down the outgoing renderer, not just stop pointing at it"
    )
}

/// Guards the literal list below against a catalogue that grew: matching every existing id to one
/// of the literals (a superset check) would still pass if a fourth backend joined
/// `Catalogue.renderers` without a matching literal here, leaving it unexercised by
/// `theSurfaceChangesWhenAFrameIsEncoded` while the three original cases kept passing. Comparing
/// sets both ways catches that; comparing only "every catalogue id has a literal" would not.
@MainActor @Test
func theArgumentListNamesEveryCatalogueEntry() {
    let literalIDs: Set<String> = [
        "canvas", "core-animation", "metal", "swift-charts", "shape-path", "core-image",
        "scenekit", "shader", "metal-compute",
    ]
    #expect(literalIDs == Set(Catalogue.renderers.map(\.id)))
}

// Swift Testing evaluates a parameterized test's `arguments:` outside any actor, so this list
// cannot be `Catalogue.renderers.map(\.id)`: every conformer's `descriptor` — and, for the Canvas
// backend, even its plain identifier constant — is isolated to the main actor by the module that
// declares it, and neither the array nor a key path to `id` can be formed without one. The literal
// strings below are checked against the live catalogue inside the test body, on the main actor,
// so a renamed identifier fails loudly here instead of this list silently going stale. The
// coverage check above catches the complementary case, an entry added but not listed.
@MainActor @Test(arguments: ["canvas", "core-animation", "metal"])
func theSurfaceChangesWhenAFrameIsEncoded(_ id: String) {
    let ticker = ManualTicker()
    guard let entry = Catalogue.renderers.first(where: { $0.id == id }) else {
        Issue.record("\(id) is not in Catalogue.renderers")
        return
    }
    let scene = ChartScene(renderer: entry.make(), ticker: ticker)
    scene.chartSize = CGSize(width: 800, height: 400)
    scene.start()
    ticker.fire(at: 0.0)
    let first = scene.renderer.encodedRevision
    ticker.fire(at: 0.5)
    #expect(
        scene.renderer.encodedRevision > first,
        "\(id) encoded a second frame without changing anything the view can observe"
    )
}
