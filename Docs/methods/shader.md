# Shader

## What it does

Draws a chart by handing SwiftUI's `colorEffect` a fragment program that decides, per pixel,
whether that pixel lies on a line — analytically, from the geometry of a segment, not from any
rasterised shape. `Rectangle().colorEffect(ShaderLibrary.default.chart_line(...))` composites one
invocation per contiguous run: `chart_line` walks that run's segments, finds the closest one to the
current pixel, and turns the distance into coverage with `smoothstep`. Nothing this backend builds
is itself a shape SwiftUI rasterises — the shape *is* the output of a program run once per output
pixel. The card's hypothesis, stated before anything was measured: this method works over the
raster, not over the data, so the line a reader sees was decided by a program running at the pixel
grid's own resolution rather than by anything resembling geometry this backend prepared in advance.

## Where it lives

| Symbol | Module |
|---|---|
| `ShaderBackend` | `ShaderBackend` |
| `ShaderLineBuffers` | `ShaderBackend` |
| `ShaderChartRenderer` | `ShaderBackend` |
| `ShaderFrame` | `ShaderBackend` |
| `ShaderSeriesBuffers` | `ShaderBackend` |
| `ShaderChartView` | `ShaderBackend` |
| `ShaderRenderer` | `ShaderBackend` |
| `ShaderRenderTarget` | `ShaderBackend` |

The fragment function itself, `chart_line`, is **not** in this table and cannot be: it lives in
`Demo/Sources/Shaders/ChartLine.metal`, outside every Swift module this package builds, for the
reason the next section states. `ShaderLineBuffers` packs buffers and touches no `Shader` or
`ShaderLibrary` value, so it is testable with no compiled shader anywhere on the host — the same
shape of split `MetalChartGeometry` has from `MetalLineRenderer`. `ShaderChartRenderer` turns a
`PreparedFrame` into a `ShaderFrame` of per-run buffers; `ShaderChartView` composites them over a
chrome `Canvas`; `ShaderRenderer` is the `ChartRenderer` conformer; `ShaderRenderTarget` renders the
view off screen for the equivalence comparison — correctly only inside a bundle that has compiled
the `.metal` file, which no target `swift test` builds ever is.

## Contract

- Input is a `PreparedFrame` — the same windowed, reduced, projected frame every other backend
  draws, so nothing about the data path differs here.
- `ShaderLineBuffers.pack(_:)` packs already-projected plot-space points into `x0,y0,x1,y1,…`
  `Float32` pairs, native-endian, at a fixed `pointStride` of 8 bytes per point — the layout
  `device const float2 *` reads with no per-element conversion, and the fact `chart_line` divides
  `byteCount` by to recover a point count.
- **The one design decision this card makes that the brief leaves open:** a `[[stitchable]]` shader
  takes a fixed argument list, so it cannot accept "one buffer per series, plus however many breaks
  that series happens to have this frame" — there is no way to hand it a variable number of
  buffers. The alternative the brief's own signature suggests — one flat buffer per series with a
  marker value where a break falls — would need the shader to scan for that marker on every pixel
  of every segment it evaluates, turning a data-layout decision into a per-pixel cost. Instead,
  `ShaderLineBuffers.runs(for:plot:)` splits each series into its contiguous runs and packs each one
  into its own buffer; `ShaderChartView` issues one `colorEffect` per run. A break becomes "one fewer
  buffer, one fewer `Rectangle` in the `ZStack`" — nothing the shader has to notice at all — at the
  cost of one more composited layer per run, paid by SwiftUI's compositor rather than by the
  fragment program.
- A run of fewer than two points has no segment to draw and is dropped by `runs(for:plot:)` rather
  than packed into an invocation that could only ever report zero coverage — the same threshold
  `MetalGeometryBuilder.appendSegments` applies to its own index buffer.
- `EncodeReport.pointsDrawn` counts every non-break point across every series — the same definition
  `ShapePathRenderer` and `MetalRenderer.samplesDrawn` both use — because `ShaderChartRenderer`
  builds these buffers itself and knows the count, unlike a backend that hands a description to a
  render server with no notion of "points" at all.
- `EncodeReport.drawCalls` is always `nil`, torn down or active: a `colorEffect` handed to
  `Rectangle` becomes whatever draw commands SwiftUI's compositor submits, on a thread this process
  does not observe — the same reasoning `ShapePathRenderer` gives for its own `nil`.
- `RendererDescriptor` reports `reportsRasterTime: false, reportsGPUTime: false`: SwiftUI's shader
  compositing happens inside the system's own render pass, which this project has no handle into —
  not a command buffer this process submitted and can time, the way `MetalChartView`'s `MTKView`
  is.

## Why this method

Every other SwiftUI-hosted backend in this project — `ShapePathBackend`, `SwiftChartsBackend` — has
SwiftUI turn a *shape* into pixels: a `Path`, a `LineMark`. A fragment shader is a different kind of
method entirely, evaluated at the destination's own resolution with no intermediate geometry a
rasteriser fills — the reason this card exists is to measure that difference directly rather than
assume it. The alternative this card rejected: building the segment-distance math into a `Shape`'s
`path(in:)` instead, which would just be `ShapePathBackend` a second time under a different name,
never actually running a program per pixel at all.

## Provenance

Signed-distance-to-a-line-segment coverage is a standard technique with no single citable origin —
the same class of "framework primitive, not a published algorithm" `scenekit.md` and `core-image.md`
report for their own methods. The nearest common description is Inigo Quilez's 2D distance function
notes for a capsule/segment SDF, which this project consulted for the closest-point clamp
(`t = clamp(dot(ap, ab) / dot(ab, ab), 0, 1)`) but does not claim as a citation: there is no paper,
session number, or fixed equation number to point a reader at, only a shape of computation common to
any renderer doing distance-to-segment coverage. `[[stitchable]]` and `Shader.Argument.data`'s
pointer-plus-byte-count convention are Apple's own SwiftUI shader API, documented by the framework
itself rather than by any external source.

## How this implementation differs from the source

There is no single source implementation — see Provenance above. What is this project's own choice:
packing one buffer per contiguous run rather than one per series (see Contract, above) — the API
constraint that forces it does not by itself dictate this particular resolution, and a project
willing to accept per-pixel marker scanning could have chosen the flat-buffer-with-markers scheme
the brief's original signature suggests instead. Antialiasing the coverage edge with a
`smoothstep(halfWidth - 0.5, halfWidth + 0.5, distance)` band, one pixel wide, is this project's own
choice of softness rather than a value any source specifies — narrower bands alias visibly at this
chart's line width, wider ones blur the stroke's edge more than the Core Graphics reference does.

## What it costs and where it lies

`encode(_:)`'s measured cost is CPU-side only: splitting each series into runs and packing each run
into a `Data` buffer, before any `colorEffect` is ever composited. What the shader itself costs —
one fragment program evaluated once per output pixel, with an inner loop over every segment of
whichever run that pixel's `Rectangle` carries — is O(pixels × segments) and entirely invisible to
this process: SwiftUI's compositor runs it inside the system's own render pass, the same limit
`RendererDescriptor.reportsGPUTime == false` states. `capabilities` is empty and stays empty until a
device run fills it in, the same as every other backend in this milestone.

**The equivalence measurement this page is supposed to report is not available from this
environment.** `Demo/Tests/ShaderRenderTargetTests.swift` is the only place in this project able to
run `chart_line` at all — `ShaderLibrary.default` resolves it only from a bundle Xcode has compiled
`Demo/Sources/Shaders/ChartLine.metal` into, and no target `swift test` builds is that bundle. This
card's own package-level checks pass in full: `ShaderLineBuffers`' packing and run-splitting are
verified byte-for-byte in `Tests/ShaderBackendTests`, and the `ShaderBackend` Xcode scheme itself
builds clean for the iOS Simulator (`xcodebuild -scheme ShaderBackend … build` succeeds). Building
the demo app and running its test target both require the platform's Metal shader compiler, and the
host this card was implemented on has no Metal Toolchain component installed — `xcodebuild
-downloadComponent MetalToolchain` fails at its own catalog-fetch step, independent of and before
any per-file compile — so `Demo/Sources/Shaders/ChartLine.metal` cannot be built here, and neither
`drawsTheSameChartAsTheReference()` nor `aShiftedRenderIsRejected()` nor
`aGappedRenderDisagreesWithAnUngappedOne()` has been run against a real compiled shader by this
card. This page states that plainly rather than reporting a number nobody measured: per rule 4 of
this project's own working rules, a cause — or here, a result — is named only after an experiment
that could have gone the other way, and no such experiment has run yet. Running `fastlane
demo_tests` on a host with a working Metal Toolchain, and updating this section with the actual
`StructuralDifference` numbers it prints, is required before this backend's row in the comparison
can be trusted.

## Verified by

- `Tests/ShaderBackendTests/ShaderLineBuffersTests.swift` — `pack(_:)` produces exactly
  `pointStride` bytes per point, in order, decodable byte-for-byte; `runs(for:plot:)` projects into
  plot-space coordinates; a break splits one series into two runs rather than one buffer with a
  marker inside it; a run of one point is dropped rather than packed; an empty series produces no
  buffers.
- `Tests/ShaderBackendTests/ShaderChartRendererTests.swift` — an undrawable plot produces no
  series; `pointsDrawn` counts every non-break point and excludes the point a lone-point run drops;
  each series keeps its own colour and index; chrome and line width pass through unchanged.
- `Tests/ShaderBackendTests/ShaderRendererTests.swift` — the descriptor reports neither raster nor
  GPU time; `pointsDrawn` matches `pointsSubmitted` on a run with no break; `drawCalls` is always
  `nil`, torn down or active; `encode(_:)` advances `encodedRevision` by exactly one each call;
  `teardown()` is idempotent, stops further encoding, and reports `0`/`nil` rather than a guess;
  `suspend()`/`resume()` are harmless however often they are called.
- `Demo/Tests/ShaderRenderTargetTests.swift` — the equivalence check against
  `CoreGraphicsReference`, a rejected one-point shift, and a gapped render disagreeing with an
  ungapped one — written, but not yet run against a compiled shader; see "What it costs and where
  it lies" above.
