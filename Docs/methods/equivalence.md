# Equivalence

## What it does

Establishes that two backends drew the same picture, before either one's timing is quoted. A
backend that quietly dropped points, lowered its antialiasing or skipped a fill wins every
benchmark it enters, so a timing comparison that has not passed this is not a comparison — it is a
race with different rules for each runner.

## Where it lives

| Symbol | Module |
|---|---|
| `ImageDifference` | `BenchRuntime` |
| `EquivalenceVerdict` | `BenchRuntime` |
| `OffscreenRenderTarget` | `CanvasBackend` |

## Contract

- Every comparison renders at **one pinned configuration**: 1024×768, 8-bit premultiplied BGRA,
  sRGB, antialiasing on, interpolation off. A comparison run at whatever size the window happened
  to be compares two different questions.
- Two renders of the same frame are **byte-for-byte identical**. Without that a difference between
  backends cannot be told from noise in the rasteriser.
- Differences are counted **per channel**, not per pixel: a pixel whose blue alone is wrong is a
  real difference, and per-pixel counting hides how much of it is wrong.
- Identical images report a peak signal-to-noise ratio of **infinity**, not a large finite number.
- A verdict is `passed`, `failed` or `notChecked` — three values, because "not checked" must never
  be readable as "passed". A `failed` case makes its whole results file unpublishable.

## Why this method

**Two bars, not one.** The fraction of samples beyond tolerance catches many small differences
spread across the frame; the signal-to-noise ratio catches a few large ones concentrated in a
corner. Either bar alone passes a case the other would fail, so both must clear.

**A tolerance of 8 of 255.** Below it a difference is attributable to rounding in the rasteriser;
above it something was drawn differently. This is a convention of the project, not a perceptual
result, and it is stated as one.

**Text is deliberately not drawn** into the reference render. Text rasterisation depends on the
installed font and on the text engine's version, so including it would invalidate a stored
reference on a machine that draws the same chart correctly. Equivalence here is about the data
path — which samples reached which pixels — not about typography.

**The reference image is a legible chart**, eight phase-shifted curves rather than the dense
zigzag used to prove that dropped points are detected. A reference image is only useful if a
difference in it is visible to whoever is looking at the failure; a solid block hides almost any
regression. The first version of this reference was the zigzag, and it was replaced for that
reason.

## Provenance

**The thresholds have no authoritative source and this page will not invent one.**

The two-bar structure — an area measure plus a peak-error measure — is standard practice in image
regression testing, and PSNR itself is textbook. What is *not* from a source: the 2 % area bar, the
35 dB ratio bar and the 8/255 tolerance. All three are this project's conventions, chosen to be
loose enough to survive rasteriser rounding and tight enough to catch a missing series. Nothing
here has been calibrated against human judgement, and no claim is made that a pair passing these
bars is perceptually identical.

What was consulted and rejected as a citation: perceptual image-difference metrics such as SSIM
and the CIE colour-difference formulae. Both are better founded and neither is implemented, because
the question being asked is "did the same samples reach the same pixels", which is a mechanical
question rather than a perceptual one.

## How this implementation differs from the source

Not applicable: there is no source for the thresholds. PSNR is computed by its usual definition,
`10·log₁₀(255² / MSE)`, over all channels of both buffers.

## What it costs and where it lies

- **Nothing is checked yet.** Every case in every stored result records `notChecked`, because no
  second backend exists to compare against. The machinery is here and the verdict is honest about
  the fact that it has not been used.
- Byte-identical determinism holds **within one machine and one OS**. Core Graphics does not
  promise identical rasterisation across versions, so a stored reference is a regression guard for
  this machine, not a cross-platform specification. That is why the stored comparison checks the
  file is a valid PNG rather than decoding it and demanding equality.
- The reference render draws no text, so a backend that got its axis labels wrong passes.
- A tolerance applied uniformly to all channels treats a difference in blue as equal to one in
  green. Human vision does not, which is exactly the perceptual question this metric declines to
  answer.

## Verified by

`OffscreenRenderTargetTests` in `CanvasBackendTests`: two renders of one frame are bit-identical,
for both the zigzag and the reference chart; a renderer given half the points is detected and fails
both bars; a few large differences fail on the ratio while clearing the area, and many small ones
fail on the area; differences at or below tolerance are not counted; identical buffers report
infinity and zero. The stored reference is checked for existence and format.

## What changed when a second rasteriser arrived

Everything above describes `ImageDifference`, which asks whether two images are the same to within
eight parts in 255. That was the right question for exactly as long as every backend rasterised
through Core Graphics. Two users of one rasteriser agree bit-for-bit, so the check passed — and a
mistake they shared, such as building every stroke colour in the wrong colour space, passed with
them.

The Metal backend does not share it. Multisampling quantises coverage to a fixed number of steps
where Core Graphics computes it analytically, so an edge pixel legitimately differs by far more
than the tolerance. On the reference chart the two agree to 32.5 dB with a worst channel of 159 —
and the difference is entirely in partially covered pixels: of the 1032 pixels Core Graphics filled
at exactly a palette colour, **none** differ. A stroke two points wide centred on a whole
coordinate, where no coverage is partial, comes out byte-identical.

So `StructuralDifference` asks a different question: a pixel the reference was certain about must
be filled the same way. Edges are where two rasterisers are allowed to disagree.

The criterion was chosen by breaking a working renderer and measuring, not by picking a number
today's code passes:

| render | mismatches among 8188 certain pixels |
|---|---|
| correct | 0 |
| one of eight series dropped | 979 |
| shifted by one pixel | 7975 |
| stroked at half width | 7037 |
| stroked at double width | 139 |

Checked by `aWrongRenderIsRejected` in `Tests/MetalBackendTests/MetalRenderTargetTests.swift`,
which runs all four broken renders on every test run.

A second measure, `mismatchesAwayFromEdges`, is reported and **is not a criterion** — the correct
render scores 133 on it, because where eight curves overlap no neighbourhood is free of edges. It
separates the cases too, but only with a threshold, and a threshold chosen to make today's code
pass is not a check.

One control that does **not** work, recorded so nobody rebuilds it: dropping every other sample.
On smooth data the min/max reduction rebuilds the same envelope, so the corrupted input scores
63.3 dB against the correct render's 32.5 — the broken picture looks more equivalent than the
honest one. The zigzag signal already in this suite is the control that bites, because alternating
extremes are what reduction cannot reconstruct.
