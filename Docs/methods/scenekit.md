# SceneKit

## What it does

Draws a 2D chart as `.line`-primitive geometry inside a 3D scene, viewed through an orthographic
camera positioned to look straight down at a plane where every node sits at `z == 0`. Each series
becomes one `SCNGeometry` with one vertex source and one `.line` element per unbroken run; the
chrome's grid and axis lines each become their own two-vertex node. Every material uses
`SCNMaterial.LightingModel.constant`, so a line's colour comes straight from its `diffuse`
property regardless of any light in the scene — this backend adds none. The card's own hypothesis,
stated before anything was measured: a 2D chart in a 3D scene is the wrong tool for the job, and
that conclusion is itself the result this backend exists to produce.

## Where it lives

| Symbol | Module |
|---|---|
| `SceneKitBackend` | `SceneKitBackend` |
| `SceneKitRenderer` | `SceneKitBackend` |
| `SceneKitChartGeometry` | `SceneKitBackend` |
| `SceneKitChartView` | `SceneKitBackend` |
| `SceneKitRenderTarget` | `SceneKitBackend` |

`SceneKitChartGeometry` builds the node tree and the camera and touches no Metal device, so it is
testable on a host with no GPU, the same as `MetalChartGeometry`. `SceneKitRenderer` owns the
`SCNScene` and camera for its whole lifetime and rebuilds the content node on every `encode(_:)`;
`SceneKitChartView` puts an `SCNView` on screen, driven by the scene's own tick rather than the
view's own render loop; `SceneKitRenderTarget` renders the same node tree off screen, through
`SCNRenderer`, for the equivalence comparison.

## Contract

- Input is a `PreparedFrame` — the same windowed, reduced, projected frame every other backend
  draws, so nothing about the data path differs here.
- Vertices are built in point space, not device pixels — `plot.minX + point.x * plot.width` on x,
  and a y flipped into SceneKit's right-handed, y-up world (`canvasHeight - pointSpaceY`) rather
  than device-pixel space the way `MetalLineGeometry` builds it. This backend's render server owns
  its own resolution scaling, the same as `CoreAnimationChartLayer`'s `CGPath`, so nothing here
  multiplies by `PreparedFrame.scale`.
- `SceneKitChartGeometry.canvasSize(for:)` recovers the frame's full canvas — width and height, not
  merely `plotRect` — by adding `FramePreparation`'s four fixed insets back onto `plotRect`'s far
  corner. `PreparedFrame` carries no canvas size of its own; this is the one place in the backend
  that needs one, to centre and scale the camera.
- The camera is orthographic, unrotated, positioned at the canvas's centre with
  `orthographicScale` set to half the canvas height. An unrotated SceneKit camera looks down its
  own -Z axis with +Y as screen-up, so this places one SceneKit unit exactly on one point of the
  canvas the frame was prepared for, provided the destination shares the canvas's aspect ratio —
  true of both the on-screen `SCNView`, sized by its host to the same frame, and the offscreen
  render target, sized to `ComparisonImage`'s pinned dimensions.
- A break in a series ends the run before it and starts a new one: the point marked `isBreak` never
  becomes a vertex, and no `SCNGeometryElement`'s index pairs cross from one run into the next — a
  separate geometry element stands in for the `move(to:)` every other backend's path-based
  rasteriser uses for the same gap. A run of fewer than two points contributes vertices but no
  element, since a single point has no segment to draw — the same treatment
  `MetalGeometryBuilder.appendSegments` gives it.
- `EncodeReport.pointsDrawn` is a real count — every non-break point across every series, the same
  definition `MetalRenderer.samplesDrawn` uses — because this backend builds its own vertex arrays
  and knows the number, unlike a backend that hands a description to a render server. It is `nil`
  on a host with no Metal device, since nothing can be delivered through `SCNView` at all there.
- `EncodeReport.drawCalls` is always `nil`: `SCNView` tessellates and submits this scene's geometry
  to the GPU on its own thread, after `encode(_:)` has already returned, the same reason Core
  Animation and Swift Charts report `nil` regardless of device.
- `RendererDescriptor` reports `reportsRasterTime: false, reportsGPUTime: false`: `SCNView`'s render
  server runs on its own thread and hands this process no command buffer to time, the way
  `MetalChartView`'s `MTKView` does.

## Why this method

SceneKit is a 3D scene graph framework; drawing a 2D chart inside one only makes sense if a project
is comparing methods a reader might actually reach for, not only the ones expected to win. Every
other backend in this project draws in 2D directly — a `CGPath`, a Metal vertex buffer, a SwiftUI
`Shape` — and SceneKit's line-drawing primitive is not built for a chart: `SCNGeometryPrimitiveType
.line` rasterises at exactly one device pixel, with no width parameter and no antialiased edge,
regardless of what width the geometry itself claims. The alternative — building the stroke's own
triangle geometry, the way `MetalLineGeometry` does — was rejected on purpose: it would make this a
Metal backend running inside a SceneKit scene, measuring Metal's own method a second time rather
than SceneKit's actual drawing primitive.

## Provenance

**SceneKit's orthographic camera and `.line` primitive are part of the framework, and this page
cites no session number or URL for either.** There is no algorithm this backend implements: it
places existing framework primitives, the same reason `core-image.md` cites no provenance for
`CIColorControls` and `CIContext`. The one piece of arithmetic that is this project's own —
recovering a canvas size from `plotRect` and `FramePreparation`'s insets, and centring an
orthographic camera on it — is standard 2D-in-3D camera placement, not a published technique with
an author to credit.

## How this implementation differs from the source

There is no source implementation to differ from — see Provenance above. What is this project's
own choice rather than the framework's: building one `SCNGeometryElement` per unbroken run instead
of one shared element per series, so a break in the data is represented structurally rather than by
an index gap a mutation could quietly bridge; keeping vertex coordinates in point space rather than
device pixels, matching the retained-mode backends' convention rather than the immediate-mode ones;
and colouring materials from `PaletteColor.cgColor` directly rather than wrapping it in `UIColor` —
`SCNMaterialProperty.contents` accepts a `CGColor` on every platform this package targets, and
`UIColor` does not exist on macOS, where `swift test` runs this exact code.

## What it costs and where it lies

`encode(_:)`'s measured cost is building the node tree itself — one `SCNGeometryElement` per
unbroken run, one `SCNGeometrySource` per series — which this backend pays on the CPU before
`SCNView`'s own render server ever sees the scene; nothing about tessellating or submitting that
geometry to the GPU is visible here, the same limit Core Animation and Swift Charts already report.
`capabilities` is empty and stays empty until a device run fills it in; this backend has not yet
had that run, and neither has any other in this milestone.

Where this method is expected to lie, stated before the measurement so the measurement can refute
it: the equivalence check below is the actual result of this card, not a footnote to it. A `.line`
primitive one device pixel wide cannot fill what this project's 1.5-point reference stroke fills,
so the certain-coverage criterion every other backend has passed — `solidMismatches == 0` — was
never going to hold here, and forcing it to would have meant building a different method inside
this one.

Measured against `CoreGraphicsReference` on the reference chart (`ComparisonImage`, `eightCurves()`,
scale 1), one representative run: 8188 solid pixels, **3541 solid mismatches** — the reference's
1.5-point stroke fills pixels a one-pixel line leaves untouched, confirming the hypothesis directly
rather than by inference — and 53131 differing pixels of 786432 (6.8%), well under the 25% "still
the same shape" observation this card treats as informative rather than as a criterion.
`solidMismatches` varies by roughly ±60 between runs of the same frame — multisampled antialiasing
resolving with some non-determinism of its own, the same class of finding `declarative-chart.md`
records for Swift Charts' render server, here on the GPU side rather than the layout side — well
inside the margin either threshold needs.

Camera and geometry placement were checked independently of those numbers: the bounding box of
solid-series-coloured pixels lands at `(52, 115)`–`(1011, 640)` in the Core Graphics reference and
`(52, 116)`–`(1011, 640)` in this backend — a one-pixel difference the narrower line itself
accounts for, not a placement error.

**Failure class:** a one-device-pixel line primitive cannot express a stroke of stated width.
Expressing a thick antialiased line in this method would require building the stroke's own
geometry — effectively a Metal backend running inside a SceneKit scene rather than using SceneKit's
own drawing primitive at all. The chart's shape and placement are otherwise correct, per the
bounding-box check above: the failure is specific to line width, not to projection, colour or
breaks.

## Verified by

- `Tests/SceneKitBackendTests/SceneKitChartGeometryTests.swift` — `canvasSize(for:)` recovers the
  canvas from `plotRect` and the fixed insets; the camera centres on the canvas at half its height
  as `orthographicScale`; a break ends one geometry element and starts a new one, checked on the
  actual decoded index buffers rather than only on rendered pixels; a run of one point between two
  breaks contributes no element; each chrome line becomes its own two-vertex element.
- `Tests/SceneKitBackendTests/SceneKitRenderTargetTests.swift` — the expected-failure equivalence
  check (`solidMismatches` large, `differingPixels` still a small fraction of the whole image); a
  one-pixel shift is rejected; the bounding box of solid series pixels lands within ten pixels of
  the Core Graphics reference's own, on every axis.
- `Tests/SceneKitBackendTests/SceneKitRendererTests.swift` — the descriptor reports neither raster
  nor GPU time; `encode(_:)` advances `encodedRevision`; `pointsDrawn` is the real per-frame count
  with a device and `nil` without one; `drawCalls` is always `nil`; `teardown()` is idempotent and
  leaves the renderer inert; `suspend()` and `resume()` are harmless however often they are called.
