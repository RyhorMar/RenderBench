# Downsampling

## What it does

A ten-second window of a 5 kHz source holds fifty thousand samples; a phone gives it four hundred
columns of pixels. Something has to decide which hundred-and-twenty-five samples per column survive
into the picture. That decision is not a performance knob — each policy discards different
information, and the one that flatters a benchmark is usually the one that lies to the reader.

Two policies are implemented, plus a faithful baseline that reduces nothing.

## Where it lives

| Symbol | Module |
|---|---|
| `downsample` | `BenchDownsampling` |
| `DownsamplePolicy` | `BenchDownsampling` |
| `runsOfMeasurements` | `BenchCore` |

## Contract

```swift
func downsample(
    _ slice: SeriesSlice,
    to targetPoints: Int,
    policy: DownsamplePolicy,
    xScale: some AxisScale,
    yScale: some AxisScale,
    into output: inout [Sample]
) throws(ChartError)
```

- **Input** must be ordered by increasing carrier. Positions flagged in `slice.gaps` carry no
  measurement.
- **Output** is written into the caller's buffer, cleared on entry and capacity retained: this runs
  once per series per frame, and a fresh allocation on that path is a measurable cost.
- **Bound.** At most `targetPoints` emitted samples, gap markers excluded — with one stated
  exception: every uninterrupted stretch contributes at least one point, so a slice broken into
  more stretches than `targetPoints` emits one point per stretch. Dropping stretches outright would
  erase intervals a reader has no way to know existed.
- **Gaps** survive. Each stretch is reduced separately, no bucket spans a dropout, and a sample
  whose value is `Double.nan` is emitted between stretches so the renderer lifts the pen.
- **Complexity** O(*n*), single pass, for every policy.
- **Precondition** `targetPoints >= 2`.
- **Throws** `ChartError.nonAveragable` when `lttb` meets a quantity whose mean is meaningless.

## Why this method

**Min/max is the default.** For a line drawn into a raster, the pixels a column lights up are
determined by the minimum and maximum of the samples falling in that column, plus the values at its
edges. Any policy that reports those four values reproduces the rasterised line exactly; any policy
that reports a "representative" sample instead cannot, once the signal's period is shorter than a
column. On the reference signal — a 400 Hz carrier in a ten-second window on a 400-point axis, so
ten carrier periods per column — the difference is visible on screen rather than arguable in prose.

**LTTB is implemented because people use it**, and because its failure is the most useful thing
this package can demonstrate. It keeps the samples that contribute most to the *perceived shape* of
a curve, which is the right goal for a slow signal read for its form and the wrong one for a fast
signal read for its amplitude.

**Neither is a data-reduction method.** Both exist to choose pixels. Feeding either into a
derivative, an FFT or a curve fit is a category error: LTTB is not band-limited and aliases content
above the bucket rate, and min/max deliberately biases towards extremes.

## Provenance

**Per-column min/max.** Jugel, U., Jerzak, Z., Hackenbroich, G., Markl, V. *M4: A
Visualization-Oriented Time Series Data Aggregation.* Proceedings of the VLDB Endowment 7(10),
2014, pp. 797–808. <https://www.vldb.org/pvldb/vol7/p797-jugel.pdf> — retrieved and verified;
the paper's result is that min, max, first and last per pixel column reproduce the line-rasterised
plot without error, which is the argument for min/max being the default here rather than a
preference.

**LTTB.** Steinarsson, S. *Downsampling Time Series for Visual Representation.* MSc thesis,
University of Iceland, 2013. §4.2 introduces Largest-Triangle-Three-Buckets. The thesis is at
<https://skemman.is/handle/1946/15343>; the host serves a bot challenge to automated retrieval, so
the metadata here was confirmed against OpenAlex (work id for the same title, author Sveinn
Steinarsson, year 2013) rather than by opening the file. Recorded because a citation nobody could
open should say so.

**LTTB at scale.** Van Der Donckt, J. et al. *MinMaxLTTB: Leveraging MinMax-Preselection to Scale
LTTB.* arXiv:2305.00332, 2023. <https://arxiv.org/abs/2305.00332> — retrieved and verified. Relevant
here as the source of the observation that min/max preselection and LTTB compose; not implemented.

## How this implementation differs from the source

- **The triangle metric is evaluated in normalised screen space, after projection through both
  scales.** The thesis does not specify a space, and implementations routinely compute it in data
  space — where the metric mixes seconds with bars, so the selected points depend on whether a
  pressure is expressed in bars or in pascals. A test pins that the same curve in two units yields
  the same selection.
- **Gap handling is ours.** The thesis has no notion of a missing sample. Each uninterrupted stretch
  is bucketed independently, so no triangle spans a dropout.
- **The bucket budget is spent, not divided.** Allocating each stretch its proportional share
  independently is unbounded in the number of stretches.
- **Min/max reports the carrier position of each extremum**, not the bucket centre, so the peak is
  drawn where it happened.
- **M4's `first` and `last` per column are not emitted.** Only the two extrema are, which is enough
  for a stroked polyline and is not enough to reproduce M4's exactness claim in full. Stated here
  because the difference matters if anyone quotes the paper's guarantee at this code.

## What it costs and where it lies

- Min/max emits up to two points per column, so a 400-point axis submits about 800 samples per
  series regardless of source rate. That is the price of the envelope.
- Min/max biases every column towards its extremes: a noisy signal looks noisier than it is, because
  the noise floor is drawn at its widest everywhere.
- LTTB collapses an envelope whose period is shorter than a bucket, and introduces a slow ripple the
  signal does not contain — an artefact of which sample each bucket happened to pick.
- LTTB is measurably *slower* than min/max here, not faster: it evaluates a triangle area per
  candidate, min/max evaluates two comparisons.
- Neither policy is applied before a numerical step anywhere in this package, and neither should be.

## Verified by

`DownsampleTests`, `BudgetTests` in `BenchDownsamplingTests`: global extrema survive min/max; LTTB
output is a subsequence with endpoints retained; changing the unit does not change LTTB's selection;
no bucket spans a gap; output respects the bound for both policies across four gap densities; an
all-gap slice emits nothing; a non-averagable quantity is refused under LTTB and accepted under
min/max.
