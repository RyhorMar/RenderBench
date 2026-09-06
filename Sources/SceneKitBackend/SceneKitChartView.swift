#if os(iOS)
import BenchCore
import BenchRuntime
import Metal
import SceneKit
import SwiftUI

/// An `SCNView` that shows one encoded scene, and nothing else.
///
/// **It does not run its own render loop.** `rendersContinuously` and `isPlaying` are both off, so
/// the view draws only when told to — `setNeedsDisplay()`, called from `updateUIView` on the
/// scene's own tick. Left at its defaults `SCNView` schedules its own frames, and this backend
/// would be measured against a different number of frames from the ones it is compared with.
public struct SceneKitChartView: View {
    private let scene: SCNScene
    private let cameraNode: SCNNode
    private let layout: ChromeLayout
    private let encodedRevision: UInt64
    private let device: MTLDevice?

    /// - Parameters:
    ///   - scene, cameraNode: Owned by `SceneKitRenderer`, not built here — a coordinator created
    ///     lazily by SwiftUI on first appearance is the wrong place to discover, and swallow,
    ///     whether this host can render at all.
    ///   - encodedRevision: Which `encode()` call produced `scene`'s current content. Threaded
    ///     through so a future reader has the same seam every other backend's view already has,
    ///     even though this view has no deferred completion of its own to tag with it.
    public init(
        scene: SCNScene,
        cameraNode: SCNNode,
        layout: ChromeLayout,
        encodedRevision: UInt64 = 0,
        device: MTLDevice? = nil
    ) {
        self.scene = scene
        self.cameraNode = cameraNode
        self.layout = layout
        self.encodedRevision = encodedRevision
        self.device = device
    }

    public var body: some View {
        ZStack {
            SceneKitChartSurface(
                scene: scene,
                cameraNode: cameraNode,
                encodedRevision: encodedRevision,
                device: device
            )
            SceneKitChartLabels(layout: layout)
        }
    }
}

/// The drawing surface. Separated so that only this view reads the per-frame revision.
struct SceneKitChartSurface: UIViewRepresentable {
    let scene: SCNScene
    let cameraNode: SCNNode
    let encodedRevision: UInt64
    let device: MTLDevice?

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero, options: [SCNView.Option.preferredDevice.rawValue: device as Any])
        view.scene = scene
        view.pointOfView = cameraNode
        view.rendersContinuously = false
        view.isPlaying = false
        view.antialiasingMode = .multisampling4X
        // No light in the scene: every material this backend builds uses `SCNMaterial
        // .LightingModel.constant`, which reads its colour straight from `diffuse` and ignores
        // lighting entirely, so the default light SceneKit would otherwise add contributes nothing
        // and only costs a render pass it does not need.
        view.autoenablesDefaultLighting = false
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        // The scene's tick, arriving as a state change. This is the only thing that requests a
        // redraw; `rendersContinuously` and `isPlaying` are both off so nothing else does.
        view.setNeedsDisplay()
    }
}

/// Axis labels, drawn by SwiftUI over the SceneKit surface, from the same layout every other
/// backend strokes — this view places no tick itself.
struct SceneKitChartLabels: View {
    let layout: ChromeLayout

    private static let labelFont = Font.system(size: 9, design: .monospaced)

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { context, _ in
            for entry in layout.labels {
                let anchor: UnitPoint = entry.anchor == .trailing ? .trailing : .center
                context.draw(context.resolve(label(entry.text)), at: CGPoint(x: entry.x, y: entry.y), anchor: anchor)
            }
        }
        .allowsHitTesting(false)
    }

    private func label(_ text: String) -> Text {
        Text(text)
            .font(Self.labelFont)
            .foregroundStyle(
                Color(.sRGBLinear, red: layout.labelColour.red, green: layout.labelColour.green, blue: layout.labelColour.blue)
            )
    }
}
#endif
