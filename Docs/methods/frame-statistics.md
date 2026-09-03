# Frame statistics

## What it does

Collects one record per frame and is the only place in the package where a percentile is computed.
The on-screen overlay and the benchmark runner both read from here and neither calculates anything
of its own, so a HUD cannot contradict the results file it was meant to illustrate.

## Where it lives

| Symbol | Module |
|---|---|
| `FrameMetrics` | `BenchRuntime` |
| `MetricsSink` | `BenchRuntime` |
| `FrameStatistics` | `BenchRuntime` |

## Contract

- **Every duration is nanoseconds**, and every field says so in its own documentation. Mixing
  milliseconds into a frame-time table silently is the most common way to get one wrong.
- **Optionals mark what a backend cannot report**, not missing data. `gpuNs` and `presentedTime` stay
  `nil` on a CPU path; a zero there would win every comparison it appeared in.
- `record(_:)` is O(1) amortised and safe to call from the frame tick.
- `summary(frameBudgetSeconds:)` returns CPU percentiles, GPU percentiles and the missed-deadline
  ratio from **one pass under one lock acquisition**, so the three figures cannot describe different
  windows.
- An empty sink reports `nil`, never zero.

## Why this method

**Nearest-rank, with no interpolation.** The percentile of a sorted sample is the value at rank
⌈p/100 × n⌉ — the smallest value at or below which at least *p* percent of observations fall. It is
chosen over the interpolating definitions for one reason: every value it reports is a frame that
actually occurred. A p95 of 11.4 ms produced by interpolating between two neighbouring frames is a
duration no frame took, and it cannot be traced back to a frame in the log.

**The definition is stated, not assumed.** There are nine defensible definitions of a sample
quantile in common use, and on a hundred-sample window they disagree by a whole frame. A table that
does not say which one it used cannot be compared with anything.

**Percentiles rather than a mean.** A mean over frame times understates a tail by a factor of three
on a realistic distribution and hides it entirely on a mild one; a median hides it completely. The
tail is what a reader feels.

## Provenance

**Sample quantile definitions.** Hyndman, R. J., Fan, Y. *Sample Quantiles in Statistical Packages.*
The American Statistician 50(4), 1996, pp. 361–365. DOI
[10.1080/00031305.1996.10473566](https://doi.org/10.1080/00031305.1996.10473566) — metadata retrieved
and verified through Crossref (the publisher serves a bot challenge to direct retrieval). The paper's
taxonomy is the reason this package names its definition rather than describing it as "the 95th
percentile"; nearest-rank is their Type 1, the inverse empirical distribution function.

**Frame deadlines.** No literature source; the rule is arithmetic on Apple's display-link contract.
`CADisplayLink` supplies `targetTimestamp`, the instant the frame being prepared is expected to
appear: <https://developer.apple.com/documentation/QuartzCore/CADisplayLink> — retrieved and verified
(iOS 3.1+, macOS 14.0+). A frame is late here when its presentation time exceeds the target by more
than half a frame budget, which is a threshold this project chose and can defend only as convention.

## How this implementation differs from the source

- Hyndman and Fan describe nine definitions; this implements **one** and names it. No selection
  parameter is exposed, because a results file whose quantile definition varies between runs is not
  comparable with itself.
- The rank is computed on the retained window only. There is no streaming estimator: the sink holds
  a bounded ring of records — twenty seconds at 120 Hz by default — and sorts it. Long-run quantiles
  over a whole session are not available and are not claimed.

## What it costs and where it lies

- `summary` sorts the retained window on every call: O(*n* log *n*) in the ring size. Called from a
  frame tick at every frame it would be a cost worth avoiding; the demo calls it every tenth frame.
- The ring is bounded, so a thermal shift partway through a run shows up as a change in the numbers
  rather than being averaged away — which is intended — but a percentile over a window that spans
  the shift describes neither state.
- `missedDeadlineRatio` is `nil` rather than zero when nothing could observe presentation. On the
  CPU-only path that is every frame, so the field is currently unknowable rather than good.
- Nothing here computes a confidence interval. A p95 without one is not a basis for "A is faster
  than B", and this package does not yet publish such a comparison.

## Verified by

`MetricsSinkTests` in `BenchRuntimeTests` and `PercentileFixtureTests` in `BenchTestSupportTests`:
percentiles match a fixture whose expected values are computed by hand from the definition rather
than by the code under test; nearest-rank handles ties and duplicates; the oldest frames fall out of
the window in order; GPU statistics are absent rather than zero when no frame reported them; a
missed deadline needs a presentation time to be knowable; the grouped summary agrees with the
individual accessors.
