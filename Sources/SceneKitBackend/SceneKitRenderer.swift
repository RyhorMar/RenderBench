import BenchHost
import BenchRuntime
import Foundation
import Metal
import SceneKit
import SwiftUI

/// `ChartRenderer` conformer for the SceneKit backend.
///
/// Owns the `SCNScene` and camera for its whole lifetime, the same way `MetalRenderer` owns its
/// device and `CoreImageRenderer` owns its context: a host with no Metal device is a fact known
/// here, in `init()`, rather than discovered later inside a `UIViewRepresentable` coordinator that
/// would otherwise have to build one lazily and swallow the failure.
@MainActor
@Observable
public final class SceneKitRenderer: ChartRenderer {
    /// Identity and reporting capabilities: `SCNView` renders on its own thread through its own
    /// render server, the same as Core Animation and Swift Charts, so neither raster nor GPU time
    /// is ever observable from here.
    public static let descriptor = RendererDescriptor(
        identifier: SceneKitBackend.identifier,
        displayName: "SceneKit",
        reportsRasterTime: false,
        reportsGPUTime: false
    )
    public static var capabilities: [Capability] { SceneKitBackend.capabilities }

    /// `nil` on a host with no Metal device. `encode(_:)` reads this, not a swallowed `try?`, to
    /// know whether anything can actually be delivered before it reports a count.
    let device: MTLDevice?
    /// Why `device` is `nil`; `nil` itself once it was found.
    let initializationFailure: SceneKitRendererError?

    /// Owned for the renderer's whole lifetime and shared with whatever `surface` returns: a
    /// `UIViewRepresentable` coordinator only ever points its `SCNView` at this scene, never
    /// builds its own.
    let scene = SCNScene()
    let cameraNode = SceneKitChartGeometry.makeCamera()
    private var contentNode = SCNNode()
    private(set) var layout = ChromeLayout.empty
    public private(set) var encodedRevision: UInt64 = 0
    private var tornDown = false

    public convenience init() {
        self.init(device: MTLCreateSystemDefaultDevice())
    }

    /// Test seam: builds a renderer as if the host had no device, without needing to fake
    /// `MTLCreateSystemDefaultDevice()` itself.
    init(device: MTLDevice?) {
        self.device = device
        self.initializationFailure = device == nil ? .noDevice : nil
        scene.rootNode.addChildNode(cameraNode)
        scene.rootNode.addChildNode(contentNode)
    }

    public func encode(_ prepared: PreparedFrame) -> EncodeReport {
        guard !tornDown else { return EncodeReport(encodeNs: 0, pointsDrawn: nil, drawCalls: nil) }
        defer { encodedRevision += 1 }

        let clock = ContinuousClock()
        var drawn = 0
        let elapsed = clock.measure {
            scene.background.contents = prepared.chrome.background.cgColor
            SceneKitChartGeometry.positionCamera(cameraNode, for: prepared)
            let (node, count) = SceneKitChartGeometry.buildContent(prepared)
            contentNode.removeFromParentNode()
            contentNode = node
            scene.rootNode.addChildNode(contentNode)
            drawn = count
        }
        layout = prepared.chrome

        // No device: nothing can be delivered this frame, and reporting the geometry's own count
        // here would be exactly the failure this project's other backends already guard against —
        // a host that cannot draw at all posting a plausible row in the table.
        guard device != nil else {
            return EncodeReport(encodeNs: elapsed.nanoseconds, pointsDrawn: nil, drawCalls: nil)
        }
        // `drawCalls` stays `nil` regardless: `SCNView` tessellates and submits this scene's
        // geometry to the GPU on its own thread, after this method has already returned, the same
        // as Core Animation's and Swift Charts's render servers.
        return EncodeReport(encodeNs: elapsed.nanoseconds, pointsDrawn: drawn, drawCalls: nil)
    }

    public func takeDeferredTimes() -> DeferredTimes { .none }

    public var surface: AnyView {
        #if os(iOS)
        AnyView(SceneKitChartView(
            scene: scene,
            cameraNode: cameraNode,
            layout: layout,
            encodedRevision: encodedRevision,
            device: device
        ))
        #else
        // `UIViewRepresentable` and `SCNView`'s iOS shape do not exist on macOS, and `swift test`
        // runs there. The real surface is exercised by `xcodebuild ... -destination
        // 'generic/platform=iOS Simulator' build`.
        AnyView(EmptyView())
        #endif
    }

    // No display link of its own: the scene sits inert between ticks, the same as every other
    // backend whose surface is a render server rather than a raw pixel buffer this type owns.
    public func suspend() {}
    public func resume() {}

    public func teardown() {
        tornDown = true
        contentNode.removeFromParentNode()
        contentNode = SCNNode()
    }
}
