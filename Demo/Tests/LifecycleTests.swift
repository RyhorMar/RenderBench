import BenchHost
import BenchRuntime
import CoreGraphics
import Metal
import Testing
@testable import RenderBenchDemo

/// Every backend, taken through stop/resume, teardown and release: the same lifecycle
/// ``SceneRegistry`` puts a screen's scene through when its route leaves the navigation path.
///
/// The identifier lists below cannot be `Catalogue.renderers.map(\.id)` — see
/// `ChartSceneTests.swift`'s own comment on `theSurfaceChangesWhenAFrameIsEncoded` for why a
/// parameterized test's `arguments:` is evaluated outside the main actor. Each list is checked
/// against the live catalogue by its own coverage test below, so a renamed or added identifier
/// fails loudly here instead of the literal quietly going stale.
private let allBackendIDs = [
    "canvas", "core-animation", "metal", "swift-charts", "shape-path", "core-image",
    "scenekit", "shader", "metal-compute",
]

private let gpuReportingBackendIDs = ["metal", "core-image", "metal-compute"]

@MainActor
private func makeScene(for id: String, ticker: ManualTicker) -> ChartScene {
    guard let entry = Catalogue.renderers.first(where: { $0.id == id }) else {
        Issue.record("\(id) is not in Catalogue.renderers")
        return ChartScene(ticker: ticker)
    }
    let scene = ChartScene(renderer: entry.make(), ticker: ticker)
    scene.chartSize = CGSize(width: 800, height: 400)
    return scene
}

@MainActor @Test
func theLifecycleArgumentListNamesEveryCatalogueEntry() {
    #expect(Set(allBackendIDs) == Set(Catalogue.renderers.map(\.id)))
}

@MainActor @Test
func theGPUReportingArgumentListMatchesTheDescriptors() {
    #expect(
        Set(gpuReportingBackendIDs) == Set(Catalogue.renderers.filter(\.descriptor.reportsGPUTime).map(\.id)),
        "reportsGPUTime changed for some backend without this file being updated"
    )
}

@MainActor @Test(arguments: allBackendIDs)
func stoppedSceneIgnoresTicks(_ id: String) {
    let ticker = ManualTicker()
    let scene = makeScene(for: id, ticker: ticker)
    scene.start()
    ticker.fire(at: 0.0)
    ticker.fire(at: 0.1)
    scene.stop()
    let framesAtStop = scene.framesDrawn
    ticker.fire(at: 0.2)
    #expect(scene.framesDrawn == framesAtStop, "\(id) drew a frame after stop()")
}

@MainActor @Test(arguments: allBackendIDs)
func backgroundStopsAndForegroundResumesWithoutLosingTheWindow(_ id: String) {
    let ticker = ManualTicker()
    let scene = makeScene(for: id, ticker: ticker)
    scene.start()
    ticker.fire(at: 0.0)
    ticker.fire(at: 0.1)
    scene.stop()
    let pointsBeforeBackground = scene.pointsPerSeries
    scene.start()
    ticker.fire(at: 0.2)
    #expect(
        scene.pointsPerSeries >= pointsBeforeBackground,
        "\(id) lost its window across a stop/start instead of continuing it"
    )
}

@MainActor @Test(arguments: allBackendIDs)
func teardownIsIdempotentAndLeavesTheRendererInert(_ id: String) {
    let ticker = ManualTicker()
    let scene = makeScene(for: id, ticker: ticker)
    scene.start()
    ticker.fire(at: 0.0)

    scene.renderer.teardown()
    scene.renderer.teardown()

    let report = scene.renderer.encode(PreparedFrame())
    // A torn-down renderer either counts its own submissions and truthfully reports zero, or
    // never had a submission count to report and stays `nil` — an optional here means "cannot
    // say", never a stand-in for zero. Never a positive number.
    #expect(
        report.pointsDrawn == nil || report.pointsDrawn == 0,
        "\(id) reported a positive pointsDrawn after teardown"
    )
    #expect(
        report.drawCalls == nil || report.drawCalls == 0,
        "\(id) reported a positive drawCalls after teardown"
    )
}

@MainActor @Test(arguments: allBackendIDs)
func sceneIsReleasedAfterTeardown(_ id: String) {
    weak var probe: ChartScene?

    autoreleasepool {
        let ticker = ManualTicker()
        let scene = makeScene(for: id, ticker: ticker)
        probe = scene
        scene.start()
        ticker.fire(at: 0.0)
        scene.stop()
        scene.renderer.teardown()
    }

    RunLoop.main.run(until: .now + 0.05)
    #expect(probe == nil, "\(id) kept its scene alive past stop/teardown and release")
}

@MainActor @Test(arguments: gpuReportingBackendIDs)
func gpuMemoryReturnsAfterTeardown(_ id: String) {
    guard let device = MTLCreateSystemDefaultDevice() else {
        Issue.record("no Metal device available to measure \(id) against")
        return
    }
    let before = device.currentAllocatedSize

    let ticker = ManualTicker()
    let scene = makeScene(for: id, ticker: ticker)
    scene.start()
    for frame in 0..<10 {
        ticker.fire(at: Double(frame) * (1.0 / 60))
    }
    scene.stop()
    scene.renderer.teardown()

    RunLoop.main.run(until: .now + 0.05)

    let after = device.currentAllocatedSize
    let oneMebibyte = 1 << 20
    #expect(
        after <= before + oneMebibyte,
        "\(id) held onto \(after - before) bytes of GPU memory after teardown"
    )
}
