# Core Image

## What it does

Delivers a raster to the screen through a GPU filter pipeline, and draws no line itself.
`CoreImageRenderer.encode(_:)` rasterises the prepared frame with
`CoreGraphicsReference.renderCGImage(_:scale:)` — the same CPU drawing every Core-Graphics-based
backend in this project is compared against — wraps the result in a `CIImage`, and runs it through
one `CIColorControls` filter. The image that filter produces is handed to an `MTKView` on the next
tick; nothing in this backend ever builds geometry or strokes a path. What it measures is the cost
of moving an already-finished picture through Core Image's GPU pipeline, not a cheaper way to draw
a chart.

## Where it lives

| Symbol | Module |
|---|---|
| `CoreImageBackend` | `CoreImageBackend` |
| `CoreImageRenderer` | `CoreImageBackend` |
| `CoreImageChartView` | `CoreImageBackend` |
| `CoreImageRenderTarget` | `CoreImageBackend` |
| `renderCGImage` | `BenchRuntime` |

`CoreImageRenderer.encode(_:)` builds a `CIImage` from `CoreGraphicsReference.renderCGImage(_:scale:)`
and a neutral `CIColorControls` filter; `CoreImageChartView` puts an `MTKView` on screen, driven by
the scene's own tick and not by the view's display link, and its `Coordinator` calls
`CIContext.render(_:to:commandBuffer:bounds:colorSpace:)` to deliver the filtered image into the
drawable's texture, timing that call on both the host's clock and the GPU's own, exactly as
`MetalRenderer` does for its draw pass. `CoreImageRenderTarget` renders the same pipeline off
screen, on a real `MTLDevice`, for the equivalence comparison. `renderCGImage(_:scale:)` is this
card's one addition to `BenchRuntime`'s `CoreGraphicsReference` — see Contract, below.

## Contract

- Input is a `PreparedFrame`, the same windowed, reduced, projected frame every other backend
  draws — nothing about the data path differs here, and this backend does not even read
  `PreparedFrame.series` directly: `CoreGraphicsReference.renderCGImage(_:scale:)` does, on this
  backend's behalf.
- `renderCGImage(_:scale:)` returns `CGContext.makeImage()` on the exact bitmap context
  `CoreGraphicsReference.render(_:scale:)` draws into and copies bytes out of. The two are the same
  pixels by construction — one context, drawn once — not two rasterisers that happen to agree, and
  a shared private `makeCanvas(_:scale:)` is what the two public entry points call so that nothing
  after this card could let them draw differently from each other.
- `saturation` is the one filter parameter this backend exposes, defaulting to
  `CoreImageRenderer.neutralSaturation` (`1`). At `1`, with brightness and contrast pinned neutral
  unconditionally, `CIColorControls` is mathematically the identity transform, and every equivalence
  test in this backend renders here. A caller passing a different value — `1.6` is what the demo's
  visibly-tinted mode would use — gets a genuinely different image, not a rounding variant; wiring
  that value into the demo catalogue is out of scope for this card.
- `EncodeReport.pointsDrawn` is always `nil`. This backend never iterates per-point geometry — it
  hands `CoreGraphicsReference` the whole frame and gets pixels back — so "how many samples did
  this frame draw" has no answer here to report, honestly, unlike a backend that builds its own
  point array.
- `EncodeReport.drawCalls` is `1` whenever a Metal device exists to deliver through, because this
  backend issues exactly one `CIContext` render per frame, to one fixed destination, and knows that
  count without guessing. It is `nil` on a host with no device, or when the CPU raster itself
  produced nothing — reporting a submission count in either case would be the fastest row in the
  table from a backend that drew nothing at all.
- The `MTKView` this backend draws into sets `framebufferOnly = false`. Core Image writes into a
  drawable's texture through its own render and compute passes, which a `framebufferOnly` texture
  refuses; `MetalChartView`'s `MTKView` needs no such setting because `MetalLineRenderer` only ever
  issues a render pass of its own.

## Why this method

The alternative this project actually compares it against is every backend that draws its own
line: Metal expands geometry on the GPU, Canvas and Core Animation stroke a path on the CPU, Swift
Charts and Shape/Path hand SwiftUI a declarative description to rasterise. Core Image draws nothing
— it is a compositing and filtering framework, not a vector rasteriser — so the only way to put a
line-shaped picture through it at all is to rasterise the line somewhere else first and hand Core
Image the result. That is not a limitation this card works around; it is the method under test. The
milestone's own hypothesis for this backend is "postprocessing, not construction," and the contract
above is what makes that a claim the numbers can support rather than a comment asserting it: the
delivered raster is provably `CoreGraphicsReference`'s own bytes, so any time this backend costs
beyond `CoreGraphicsReference`'s own CPU rasterisation is Core Image's delivery cost and nothing
else.

## Provenance

**`CIColorControls` and `CIContext` are part of Core Image, and this page cites no session number
or URL for either.** There is no algorithm to attribute: this backend performs no filtering
computation of its own, and Apple does not publish `CIColorControls`'s kernel source or
`CIContext`'s Metal-backed scheduling. This mirrors `declarative-chart.md`'s and `shape-path.md`'s
own provenance sections for the same reason — a call into a closed-source framework has no written
source to differ from.

## How this implementation differs from the source

There is no source implementation to differ from — see Provenance above. What is this project's own
choice rather than the framework's: rasterising through the shared `CoreGraphicsReference` helper
rather than this backend's own Core Graphics drawing, so the delivered raster is provably identical
to the reference every other backend is checked against instead of merely similar to it; pinning
brightness and contrast neutral unconditionally and exposing only `saturation`, since nothing in
this project needs the other two to vary; and drawing axis labels through a separate SwiftUI
`Canvas` overlay, the same choice `MetalChartView` makes and for the same reason —
`CoreGraphicsReference` deliberately never draws text, so a label anywhere on screen has to come
from somewhere else.

## What it costs and where it lies

`encode(_:)`'s measured cost is `CoreGraphicsReference`'s own CPU rasterisation — the same
`BitmapCanvas`-backed Core Graphics drawing `CoreAnimationRenderTarget` and `ShapePathRenderTarget`
already pay for their own comparison images — plus building a `CIImage` and describing one filter
node, which Core Image does not execute until `CIContext.render(_:to:commandBuffer:bounds:colorSpace:)`
is called later. `capabilities` is empty and stays empty until a device run fills it in; this
backend has not yet had that run, and neither has any other in this milestone.

Where this method is expected to lie, stated before the measurement so the measurement can refute
it: strictly slower than Metal's own rasterisation for the same chart, because every frame pays a
full CPU rasterisation Metal's vertex shader never performs, on top of whatever Core Image's GPU
delivery costs on its own. If that does not hold, the interesting result is why.

## Verified by

- `Tests/CoreImageBackendTests/CoreImageRenderTargetTests.swift` — at the neutral filter parameters,
  the delivered raster passes the structural comparison against the Core Graphics reference; a
  one-pixel shift is rejected; a render at `saturation: 1.6` differs from the neutral one, so the
  parameter is not provably inert.
- `Tests/CoreImageBackendTests/CoreImageRendererTests.swift` — the descriptor reports both raster
  and GPU time; `encode(_:)` advances `encodedRevision`; `pointsDrawn` is always `nil`; `drawCalls`
  is `1` with a device and `nil` without one, both while active and after `teardown()`;
  `saturation` defaults to the neutral value; `teardown()` is idempotent and leaves the renderer
  inert; `suspend()` and `resume()` are harmless however often they are called.
