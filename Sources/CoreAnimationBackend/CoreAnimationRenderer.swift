import BenchHost
import BenchRuntime
import Foundation
import QuartzCore
import SwiftUI

#if os(iOS)
import UIKit
#endif

/// `ChartRenderer` conformer for the Core Animation backend.
///
/// Owns one `CoreAnimationChartLayer` for its whole lifetime and hands the same instance to every
/// `surface` it returns, so a rebuilt `AnyView` never means a rebuilt layer tree.
@MainActor
@Observable
public final class CoreAnimationRenderer: ChartRenderer {
    /// Identity and reporting capabilities: the render server rasterises this backend's layer
    /// tree on its own thread, after `encode(_:)` has already returned, so neither raster nor GPU
    /// time is ever observable here.
    public static let descriptor = RendererDescriptor(
        identifier: CoreAnimationBackend.identifier,
        displayName: "Core Animation",
        reportsRasterTime: false,
        reportsGPUTime: false
    )
    public static var capabilities: [Capability] { CoreAnimationBackend.capabilities }

    /// Not `private`: a test needs to see that `encode(_:)` actually reached this layer. Declaring
    /// it `let` rather than `var` is unrelated to that visibility — `@Observable` only rewrites
    /// `var` stored properties for its own tracking, so a `let` here is untouched either way.
    let layer = CoreAnimationChartLayer()
    public private(set) var encodedRevision: UInt64 = 0
    private var tornDown = false

    public init() {}

    public func encode(_ prepared: PreparedFrame) -> EncodeReport {
        guard !tornDown else { return EncodeReport(encodeNs: 0, pointsDrawn: 0, drawCalls: 0) }
        defer { encodedRevision += 1 }
        // Driven from `PreparedFrame.scale` rather than read from a window here: the scale this
        // frame was projected at is already on the frame, and a second source for the same number
        // — the host view's own screen — would only give the two a chance to disagree.
        layer.renderScale = CGFloat(prepared.scale)
        let result = layer.update(with: prepared)
        return EncodeReport(
            encodeNs: result.encodeNs,
            pointsDrawn: result.pointsDrawn,
            // The render server tessellates and submits each shape layer to the GPU on its own
            // thread, after this method has already returned, so how many submissions that costs
            // is not something this process observes — only how many layers it dirtied, which is
            // a different quantity from every other backend's `drawCalls`. `nil` is the honest
            // answer, not `shapeLayerCount` standing in for a number this backend cannot know.
            drawCalls: nil
        )
    }

    // Presentation is the render server's, on its own thread, after this method has already
    // returned — there is nothing here to time.
    public func takeDeferredTimes() -> DeferredTimes { .none }

    public var surface: AnyView {
        #if os(iOS)
        AnyView(CoreAnimationHostView(layer: layer))
        #else
        // `UIViewRepresentable` does not exist outside iOS, and `swift test` runs on macOS. The
        // real surface is exercised by `xcodebuild ... -destination 'generic/platform=iOS
        // Simulator' build`; this branch exists only so the conformance compiles there too.
        AnyView(EmptyView())
        #endif
    }

    // No display link of its own: the layer tree sits inert between ticks, and hiding it while
    // backgrounded would only make it pay to redraw on return.
    public func suspend() {}
    public func resume() {}

    public func teardown() {
        tornDown = true
        layer.removeFromSuperlayer()
        layer.sublayers = nil
        layer.releaseGeometry()
    }
}

#if os(iOS)
/// Hosts a `CoreAnimationChartLayer` inside SwiftUI.
///
/// Wraps the layer as a sublayer of a plain `UIView` rather than replacing the view's own layer:
/// the layer instance is owned and reused by ``CoreAnimationRenderer``, and `UIView.layerClass`
/// can only vend a type, not hand back a specific existing instance.
struct CoreAnimationHostView: UIViewRepresentable {
    let layer: CoreAnimationChartLayer

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.layer.addSublayer(layer)
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        layer.frame = view.bounds
    }
}
#endif
