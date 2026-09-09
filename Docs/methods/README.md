# Methods

One page per family of algorithms this package implements. The point is comparison: two methods
that answer the same question are described side by side, in the same shape, so a reader can see
what each one costs and where each one lies.

## Pages

| Page | Methods | Authoritative source exists |
|---|---|---|
| [Downsampling](downsampling.md) | per-column min/max, LTTB, no reduction | yes |
| [Axis ticks](axis-ticks.md) | nice numbers, clock ladder, label collision | partly |
| [Frame statistics](frame-statistics.md) | nearest-rank percentiles, deadline detection | yes |
| [Randomness and signals](randomness-and-signals.md) | SplitMix64, Box–Muller, signal models | yes |
| [Buffers and windows](buffers-and-windows.md) | mirrored ring buffer, gap runs, carrier search | partly |
| [Frame pipeline](frame-pipeline.md) | one clock per scene, one-deep slot, epochs | no |
| [Colour](colour.md) | linear sRGB, categorical series set, three family colours | yes |
| [GPU line expansion](gpu-lines.md) | instanced quads, 4x multisampling, GPU timestamps | no |
| [Equivalence](equivalence.md) | per-channel difference, PSNR, offscreen reference | no |
| [Declarative chart](declarative-chart.md) | Swift Charts `LineMark`, run-splitting at breaks | no |
| [Shape and Path](shape-path.md) | retained SwiftUI `Shape` per series, index-marked breaks | no |
| [Core Image](core-image.md) | CPU raster delivered through a `CIColorControls` GPU filter | no |
| [SceneKit](scenekit.md) | 2D chart as `.line`-primitive geometry in a 3D scene, orthographic camera | no |
| [Shader](shader.md) | analytic segment-distance coverage in a SwiftUI `colorEffect` fragment program | no |
| [GPU compute reduction](gpu-compute-reduction.md) | per-column MinMax on the GPU, bucketed by normalised x after projection | no |

## What each page contains

Every page follows the same eight sections, in this order:

1. **What it does** — one paragraph, no code.
2. **Where it lives** — the symbols, as a table. Checked by CI: a symbol named here must exist.
3. **Contract** — inputs, outputs, complexity, preconditions.
4. **Why this method** — the alternatives, and why they were rejected.
5. **Provenance** — author, work, year, section or equation, and a URL that was fetched.
6. **How this implementation differs from the source** — mandatory. "It does not" is an answer.
7. **What it costs and where it lies** — the limits, stated by us rather than discovered by a reader.
8. **Verified by** — the tests that hold the claims up.

## Two rules

**Provenance is never omitted.** Where no authoritative source exists, section 5 says so and lists
what was consulted and why it does not qualify. Four of these methods rest on conventions with no
citable origin, and each says as much on its own page. A method presented without provenance reads
as one whose provenance nobody checked.

**No reference is written down before it is fetched.** Every URL in these pages was retrieved and
its metadata compared against the citation. Where a publisher blocks automated retrieval, the page
records that fact and names the independent index the metadata came from, rather than quietly
citing something nobody opened.

## Keeping this in step with the code

`swift run CheckMethodDocs` — part of `fastlane ci` — fails when a symbol named on a page has
disappeared from `Sources/`, and when a doc comment points at a page or anchor that does not exist.
It does not check that the prose is true; nothing can. It checks that the prose is still about
code that exists, which is the failure mode documentation actually has.

Adding an algorithm means adding it to a page, or adding a page. A method that reaches `main`
undocumented is the same defect as one that reaches `main` untested.
