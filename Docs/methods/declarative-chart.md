# Declarative chart

## What it does

Hands the same windowed, reduced, projected points every other backend draws to SwiftUI's own
`Chart` view, one `LineMark` per point, grouped into a run by a key this backend assigns. Layout,
scaling and rasterisation from there on belong to the framework: this is the first backend in the
package that does not decide where a point lands on screen, only which points exist and which run
each belongs to.

## Where it lives

| Symbol | Module |
|---|---|
| `SwiftChartsRenderer` | `SwiftChartsBackend` |
| `SwiftChartsChartView` | `SwiftChartsBackend` |
| `SwiftChartsChartRenderer` | `SwiftChartsBackend` |
| `SwiftChartsRenderTarget` | `SwiftChartsBackend` |
| `PlottedMark` | `SwiftChartsBackend` |

`SwiftChartsChartRenderer.encode(_:)` builds `[PlottedMark]` from a `PreparedFrame`, splitting
each series at every point where `PlottedPoint.isBreak` is true; `SwiftChartsChartView` hands that
array to `Chart` and draws this package's own chrome underneath, in a `Canvas`; `SwiftChartsRenderer`
is the `ChartRenderer` conformer; `SwiftChartsRenderTarget` renders the real view off screen,
through `ImageRenderer`, for the equivalence comparison.

## Contract

- Input is a `PreparedFrame`, windowed, reduced and projected into `0...1` on both axes exactly
  like every other backend's input — nothing about the data path differs here.
- A run key is `"<seriesIndex>-<runIndex>"`. Two marks share a `LineMark` series, and therefore a
  drawn line, only when they share a key; a break always starts a new key, never a new point at
  the break's own placeholder coordinates. That is the whole of this backend's own contribution:
  everything after the key is assigned is `Chart`'s decision, not this package's.
- `Chart`'s own axes and grid are hidden — `chartXAxis(.hidden)`, `chartYAxis(.hidden)` — and this
  package's chrome is drawn underneath from `PreparedFrame.chrome` instead, padded to
  `PreparedFrame.plotRect` exactly. Not because Swift Charts' own axis styling is wrong: because
  the comparison this project runs is about how nine methods place a stroke on a curve, and a
  tenth variable — which one's tick labels a reader prefers — has no business in that comparison.
  Turning them back on and comparing the two is a property a demo could add on top of this
  backend; it is not part of what `SwiftChartsRenderer` measures.
- `pointsDrawn` is a real count, not `nil`: this backend builds the mark array itself, so how many
  marks it built is a fact it has, unlike a retained-mode backend whose render server tessellates
  marks nobody upstream can see. `drawCalls` is `nil` for exactly that retained-mode reason —
  `Chart`'s own render server compiles and submits whatever it submits on a thread this process
  does not observe, and a mark count is a different quantity from a submission count.
- Two renders of one unchanged frame are **not** guaranteed bit-identical, unlike every backend
  that rasterises through code this package owns. Measured directly (see `Verified by` below):
  one render in forty disagreed with its predecessor, at up to 3 864 of 3 145 728 bytes, every one
  of them by exactly 1 of 255 — `Chart`'s own render server settling internal state this package
  cannot see, not this backend drawing anything differently.

## Why this method

The alternative this project actually compares it against is every other backend: build the
geometry and drive a lower-level drawing API by hand. `Chart` is the one case in the matrix where
that choice is made *for* the caller — layout, axis ticks, and the line's own rasterisation are the
framework's, not this package's. A method with no per-frame control over its own cost is expected
to be the first of the nine to show it, which "What it costs and where it lies" below confirms.

## Provenance

**Swift Charts is Apple's own framework, introduced at WWDC 2022, and this page cites no session
number or URL for it.** Fetching Apple's documentation page for the framework failed with a
connection reset during this session, and no independent index was reachable either, so nothing
here is stated as a retrieved fact rather than as what this project observed by using the
framework directly. There is no academic provenance to cite in the first place: unlike the GPU
line expansion in `gpu-lines.md`, this is not an algorithm this package implements from a written
source — it is a call into a framework whose internals are not published, and "how `Chart` lays
out and rasterises a `LineMark`" is exactly the part of this method this page cannot describe from
the inside.

## How this implementation differs from the source

There is no source implementation to differ from — see Provenance above. What is this project's
own choice rather than the framework's: hiding `Chart`'s axes and drawing this package's chrome
instead, splitting series into runs by key rather than by any mechanism `Chart` itself offers for
gaps, and pinning `chartXScale`/`chartYScale` to `0...1` rather than letting the framework choose a
domain — the same normalisation `FramePreparation` already performs for every other backend, kept
rather than undone so this backend's plot matches the others pixel-for-pixel.

## What it costs and where it lies

Building `[PlottedMark]` in `SwiftChartsChartRenderer.encode(_:)` is O(*n*) and cheap; it is not
where this method's cost is expected to be. The hypothesis this backend exists to test — that a
declarative chart degrades already at thousands of points — is about `Chart`'s own layout and
rasterisation, which this package cannot instrument from the outside, and which no test in
`Tests/SwiftChartsBackendTests` measures a duration for.

One observation, run once in the iOS Simulator (iPhone 17 Pro, iOS 26.5), not a device, and not
filed as a measurement: with this backend temporarily wired into the demo for the run and removed
again afterwards, the project's "400 Hz carrier" scenario with downsampling set to "None" — 49 999
points, one series — held the demo's own HUD `fps` counter at **1**, against 60 for the same
backend on the well-behaved eight-series case moments earlier and against 60 for every other
backend on this same carrier scenario at the policies that reduce it. `prep p95` (this package's
own windowing and mark-building, not `Chart`'s draw) stayed at 18 ms; the collapse is downstream of
this backend's own code, inside `Chart`'s layout and rasterisation, which is exactly the part
neither this backend nor this page can instrument. This confirms the "degrades already at
thousands of points" hypothesis at the first count tried, on the simulator's GPU
(`Apple iOS simulator GPU`, family `apple1`) — a host translation layer, not a phone. The number is
not a limit for `capabilities` and does not belong in `Benchmarks/results/` for exactly the reason
`gpu-lines.md` gives for its own simulator GPU: no number from it describes any device.

## Verified by

- `Tests/SwiftChartsBackendTests/SwiftChartsChartRendererTests.swift` — a break ends a run rather
  than being connected across it; an undrawable plot produces no marks; every mark carries its
  series' colour.
- `Tests/SwiftChartsBackendTests/SwiftChartsRendererTests.swift` — `encode(_:)` advances
  `encodedRevision`; `pointsDrawn` accounts for every submitted point when none is a break;
  `drawCalls` is `nil`; `teardown()` is idempotent and leaves the renderer inert; `suspend()` and
  `resume()` are harmless however often they are called.
- `Tests/SwiftChartsBackendTests/SwiftChartsRenderTargetTests.swift` — the real view, rendered off
  screen through `ImageRenderer`, passes the structural comparison against the Core Graphics
  reference; a one-point shift is rejected; two renders of the same frame agree to within one
  level of 255, the tolerance the "not bit-identical" observation above measured; a gapped render
  disagrees with an otherwise identical ungapped one.
