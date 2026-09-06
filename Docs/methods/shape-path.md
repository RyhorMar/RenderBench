# Shape and Path

## What it does

Turns the same windowed, reduced, projected points every other backend draws into one retained
SwiftUI `Shape` per series: a `PolylineShape` holding absolute plot-space points and the indices
where its source series broke. `encode(_:)` builds that value once; from there SwiftUI owns it,
decides when to call `path(in:)`, and rasterises the result on its own render server. This is the
first backend in the package built from `Shape` rather than a layer tree
(`CoreAnimationBackend`) or a redraw closure this process runs itself every tick (`CanvasBackend`).

## Where it lives

| Symbol | Module |
|---|---|
| `PolylineShape` | `ShapePathBackend` |
| `ShapePathChartRenderer` | `ShapePathBackend` |
| `ShapePathChartView` | `ShapePathBackend` |
| `ShapePathRenderer` | `ShapePathBackend` |
| `ShapePathRenderTarget` | `ShapePathBackend` |

`ShapePathChartRenderer.encode(_:)` turns a `PreparedFrame` into one `ShapePathSeries` per series
— absolute points with breaks removed, plus the index each removed break left behind;
`ShapePathChartView` hands each series' points and breaks to its own `PolylineShape`, stroked in a
`ZStack` over this package's chrome, drawn from `PreparedFrame.chrome` in a `Canvas` beneath;
`ShapePathRenderer` is the `ChartRenderer` conformer; `ShapePathRenderTarget` renders the real view
off screen, through `ImageRenderer`, for the equivalence comparison.

## Contract

- Input is a `PreparedFrame`, windowed, reduced and projected into `0...1` on both axes exactly
  like every other backend's input — nothing about the data path differs here.
- `PolylineShape.points` are absolute plot-space coordinates, not the `0...1` values
  `PreparedFrame` carries: `ShapePathChartRenderer` projects them into the plot rectangle once, the
  same conversion `CanvasChartRenderer` performs, so `path(in:)` can ignore the rectangle SwiftUI
  offers it entirely rather than re-deriving a layout that could disagree with the one already
  computed from `PreparedFrame.plotRect`.
- A break never becomes a point. `ShapePathChartRenderer` records the index in `points` the break
  fell before, in `PolylineShape.breaks`; `path(in:)` starts a new subpath — `move(to:)` — at that
  index instead of connecting it to the point before the gap with `addLine(to:)`. One `Shape` per
  *series*, not per contiguous run: a `Path` holds as many disjoint subpaths as it is given moves
  for, so a break inside one series' `PolylineShape` costs nothing beyond the index that marks it.
- `pointsDrawn` is a real count, not `nil`: this backend builds the points array itself, so how
  many points it built is a fact it has, unlike a retained-mode backend whose render server
  tessellates geometry nobody upstream can see. `drawCalls` is `nil` for exactly that retained-mode
  reason — `.stroke(_:style:)` hands `PolylineShape` to SwiftUI's own render server, which compiles
  and submits whatever it submits on a thread this process does not observe, and a point count is
  a different quantity from a submission count.
- `animatableData` is deliberately not implemented on `PolylineShape` in this card. Interpolating
  between two point arrays is what a retained `Shape` backend would need for a zoom or pan
  animation to move continuously rather than jump frame to frame — out of scope for this milestone
  — so what this backend measures here is a `Shape` with a stable identity per series and nothing
  more: architecturally closer to a `Canvas` that SwiftUI, not this process, decides when to
  redraw, than to the animated polyline the original hypothesis names.

## Why this method

The alternative this project actually compares it against is every other backend: build the
geometry and either stroke it inside a redraw closure this process runs every tick (`Canvas`) or
hand a layer tree to Core Animation (`CoreAnimationBackend`). `Shape` sits between the two: like
`Canvas`, this backend owns its own geometry and projection; like Core Animation, what it hands
SwiftUI is a retained value whose rasterisation happens later, on a thread this process does not
control. Measuring that value's own second-order cost — one `Shape` per series' `path(in:)` call —
against the other two is the reason a `Shape`-per-series backend belongs in the matrix at all
rather than being redundant with either neighbour.

## Provenance

**`Shape` is part of SwiftUI, introduced at WWDC 2019, and this page cites no session number or
URL for it.** There is no algorithm to attribute here in the sense `gpu-lines.md` has one: turning
points into `move(to:)`/`addLine(to:)` calls is the same operation `CanvasChartRenderer` and
`CoreGraphicsReference` both already perform, and what is specific to this backend —
`path(in:)`'s own scheduling and how SwiftUI's render server rasterises the result — is exactly
the part of `Shape` whose internals Apple does not publish. This mirrors `declarative-chart.md`'s
own provenance section for the same reason: a call into a closed-source framework has no written
source to differ from.

## How this implementation differs from the source

There is no source implementation to differ from — see Provenance above. What is this project's
own choice rather than the framework's: recording breaks as indices into an already-filtered point
array rather than leaving placeholder points in it for `path(in:)` to skip, keying each series'
view in `ForEach` by its own index rather than by position so a series keeps the identity SwiftUI
already tracks for it across frames, and drawing this package's chrome underneath in a `Canvas`
exactly as `CanvasChartView` and `SwiftChartsChartView` both do, rather than through any chrome
mechanism `Shape` itself offers — it offers none.

## What it costs and where it lies

Building `[ShapePathSeries]` in `ShapePathChartRenderer.encode(_:)` is O(*n*) in the points a frame
carries, and it is not where this method's cost is expected to be. The hypothesis this backend
exists to test — roughly two thousand points holding an animated frame budget — is about
`path(in:)`'s own call frequency and SwiftUI's render server rasterising the result, neither of
which this package can instrument from the outside or measure without a device. `capabilities` is
empty and stays empty until a device run fills it in; a limit stated before it is measured is a
hypothesis wearing a contract's clothes, and this backend has not yet had that run.

## Verified by

- `Tests/ShapePathBackendTests/PolylineShapeTests.swift` — a break starts a new subpath rather
  than connecting across it; two adjacent breaks do not produce an extra empty subpath; no break
  produces exactly one subpath.
- `Tests/ShapePathBackendTests/ShapePathChartRendererTests.swift` — an undrawable plot produces no
  series; a break is recorded as an index rather than becoming a point, and `pointsDrawn` accounts
  for every submitted point once breaks are subtracted; every series carries its own colour and
  index.
- `Tests/ShapePathBackendTests/ShapePathRenderTargetTests.swift` — the real view, rendered off
  screen through `ImageRenderer`, passes the structural comparison against the Core Graphics
  reference; a one-point shift is rejected; `pointsDrawn` matches `pointsSubmitted` on a fixture
  with no breaks; a gapped render disagrees with an otherwise identical ungapped one.
- `Tests/ShapePathBackendTests/ShapePathRendererTests.swift` — `encode(_:)` advances
  `encodedRevision`; `pointsDrawn` accounts for every submitted point when none is a break;
  `drawCalls` is `nil`, both while active and after `teardown()`; `teardown()` is idempotent and
  leaves the renderer inert; `suspend()` and `resume()` are harmless however often they are called.
