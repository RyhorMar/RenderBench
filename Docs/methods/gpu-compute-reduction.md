# GPU compute reduction

## What it does

Reduces a series on the GPU instead of drawing an already-reduced one. Every other backend
receives a `PreparedFrame` whose points `BenchDownsampling` has already cut down to the display's
resolution; this one asks the scene to skip that step — `RendererDescriptor.reducesOnGPU` says
so — and receives every windowed point instead. `encode(_:)` splits each series at its breaks,
buckets each resulting run along its own span of normalised x, and dispatches one GPU thread per
bucket to find that bucket's minimum and maximum. Only once that result is read back does the
draw itself happen, through the same instanced-quad line pass `MetalBackend` uses. The question
this backend exists to answer: does moving MinMax reduction onto the GPU change the picture.

## Where it lives

`Sources/MetalComputeBackend/`. `RunSplitter` turns a prepared series into breakless runs and
touches no Metal type, so it is testable on a host with no GPU; `MetalComputeReducer` owns the
device and the compute pipeline, dispatches one thread per output column, and performs the one
synchronous readback per frame this method's contract requires; `MetalComputeChartGeometry` builds
the pixel-space line geometry from what came back; `MetalComputeLineRenderer` draws it;
`MetalComputeRenderTarget` renders off screen for the equivalence comparison; `MetalComputeRenderer`
is the `ChartRenderer` conformer that ties the three together.

## Contract

- Input is a `PreparedFrame` prepared at `DownsamplePolicy.none`: every point in the window,
  already projected into normalised `0...1` on both axes, with `isBreak == true` marking a gap. A
  break point's coordinates are always the placeholder `(0, 0)` and are never real data.
- A break ends one run and starts the next, exactly like every other backend's treatment of a
  gap — no bucket this backend builds ever spans one.
- Per run, `columns = max(1, Int(runWidthNormalised * plot.width))`, where `runWidthNormalised` is
  that run's own `(maxX - minX)` among its own points. This mirrors `FramePreparation`'s own
  `target = max(2, Int(plot.width))` sizing for the whole-frame case, applied per run instead,
  since this backend never sees a whole frame's carrier range — only what already reached it as
  normalised x.
- Each bucket emits the point with the minimum y and the point with the maximum y it contains, in
  carrier order — whichever occurred first in the run, not always minimum-then-maximum, since the
  wrong order draws the line backwards inside the bucket. Both `<` and `>` are strict, so a tie
  resolves to the first occurrence, matching `BenchDownsampling.appendMinMax`'s own tie-breaking
  for the same reason.
- `x`/`y` inside the kernel are plain `float`. Safe here specifically because every coordinate this
  backend receives is already normalised to `0...1` — the project's `Double`-for-time rule exists
  because of unix time's ULP at its current magnitude, a hazard with no counterpart in a unit range.
- `EncodeReport.pointsDrawn` counts points **after** reduction, read back from the GPU. The
  readback is synchronous and its cost is included in `encodeNs`, not hidden outside it.

## Why this method

Every other backend times how a method draws a picture nine ways; this one asks whether the
picture's own construction — the reduction step every one of them takes for granted as a CPU
preprocessing pass — has to happen on the CPU at all. Doing it in a compute kernel rather than a
fragment or vertex stage is what makes the reduction itself the measured method instead of an
input to it.

## Provenance

The instanced-quad line pass this backend draws with after reducing is the same one
`Docs/methods/gpu-lines.md` documents and cites; nothing new is claimed for it here. The
per-column MinMax reduction itself follows no published GPU algorithm — it is this project's own
per-run adaptation of the same idea `BenchDownsampling.appendMinMax` implements on the CPU, changed
exactly where the next section says it changes.

## How this implementation differs from the source

This does **not** reproduce `BenchDownsampling.appendMinMax` bit-for-bit on irregular or
multi-segment data, and the difference is deliberate rather than an oversight:

- The CPU path buckets by **raw carrier**, before projection; this backend buckets by
  **normalised x, after projection** — it never receives carrier/value pairs at all, only what
  `FramePreparation` already projected. On a nonlinear time-to-x mapping the two would choose
  different points; the project's own `TimeScale` is affine, so on data sampled at a constant rate
  the two bucket boundaries coincide.
- The CPU path splits one shared point budget across every gap-separated stretch of a slice at
  once (`Sources/BenchDownsampling/Downsample.swift`'s `remainingBudget` bookkeeping); this backend
  sizes each run's bucket count independently, from that run's own share of the plot's width, with
  no cross-run budget to divide. A slice with several short runs and one long one would receive a
  different point count per run from the two paths.
- A bucket with no point in its x range emits nothing here; the CPU path cannot produce an empty
  bucket in the interior of a stretch by construction, since its bucket edges are placed from the
  data itself only at the coarse end (`budget == 1`) case.

On the project's own reference fixture (`eightCurves()`: one contiguous run per series, regularly
sampled, no gaps) these deviations do not appear — one run, one budget, evenly spaced points, an
affine projection — so the two are expected to converge closely there. Measured against
`CoreGraphicsReference.render(_:)` on that fixture, CPU-reduced at `policy: .minMax`: **0 of 8188
solid pixels disagree**, 132 mismatches away from edges — matching `Docs/methods/gpu-lines.md`'s
own numbers for `MetalBackend` on the identical fixture, since both draw through the same line
pass and both were handed the same points to draw once the two reductions had each run. This is
not a general equivalence guarantee: it is what one fixture chosen to look nothing like an
adversarial case for either algorithm happens to show.

## What it costs and where it lies

The library — the reduction kernel and the line pass together, one source string, compiled once
per renderer — is paid at construction, not per frame, for the same reason `MetalBackend`'s shader
is. The reduction itself costs a GPU dispatch per run and, unavoidably, a wait: `pointsDrawn` is
not known until the result is back, so `MetalComputeReducer.reduce(runsPerSeries:plotWidth:)`
calls `commandBuffer.waitUntilCompleted()` before returning, and that wait sits inside `encode(_:)`'s
own timed section. No other backend in this project pays a GPU-round-trip cost in `encode(_:)`
itself; every other backend's GPU work happens later, inside its own draw pass, off the critical
path this method's own contract puts it on.

Buffers for the reduction are allocated fresh per run per frame rather than pooled in a ring the
way `MetalLineRenderer`'s draw buffers are. That is a real, uncharged simplification: a device
whose frame is dominated by allocator churn rather than by the reduction or the wait would show it
here first.

## Verified by

- `Tests/MetalComputeBackendTests/MetalComputeReducerTests.swift` — the kernel's output matches a
  fresh, independently written Swift implementation of this backend's own normalised-x bucketing
  algorithm (not `BenchDownsampling.appendMinMax`, for the reasons above) to `1e-5` in `Float`;
  one- and two-point runs are handled without a missing partner; the wire layout the kernel writes
  and Swift reads matches by an explicit size assertion; two series dispatched together are read
  back without mixing.
- `Tests/MetalComputeBackendTests/MetalComputeRenderTargetTests.swift` — the reduced-and-drawn
  chart passes the same structural comparison against the Core Graphics reference every other
  backend is judged against; a shifted render and a render with a bridged gap are both rejected;
  `RunSplitter` ends a run at every break.
- `Tests/MetalComputeBackendTests/MetalComputeRendererTests.swift` — `encodedRevision` advances
  once per `encode(_:)` call and stops advancing once torn down; `pointsDrawn` and `drawCalls` are
  known zeros after teardown rather than a fabricated stand-in for `nil`, and `nil` on a host with
  no device; a 20 000-point window reduces to under a quarter of that after this backend's own
  GPU pass.
