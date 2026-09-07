# ADR-0002: The renderer contract is frozen after nine implementations

- Status: accepted
- Date: 2026-09-07

## Context

A protocol nine independent methods implement is worth more the fewer surprises it holds for the
sixth conformer that the first three did not already surface. This project's own decision record
(D22) set the freeze point after three, on the reasoning that three real implementations are
enough evidence and a fourth would only be guessing at what a fifth needs. In practice the
protocol changed twice more after the third conformer — once from a design review before any
conformer existed, once from what the fourth through ninth actually required — and both rounds are
worth recording here rather than only in commit history, because a reader deciding whether to
build a tenth backend needs to know what is still open to change and what is not.

## What changed after the third backend, and which backend forced it

Two changes reached the protocol after Canvas, Core Animation and Metal had already conformed:

**`EncodeReport.pointsDrawn` and `.drawCalls` became `Int?`.** A Metal-family renderer constructed
on a host with no GPU device returned real timing and a `pointsDrawn` copied straight from the
input, having drawn nothing — the fastest row in a table meant to measure drawing. Making both
fields optional, with `nil` meaning "this backend cannot report this" rather than a fabricated
count, closed that; a torn-down or device-less renderer now says so instead of winning by
omission.

**`drawCalls` gained one definition every conformer must obey, not nine private ones.** Before this
the same picture produced 1, 1 and 2 for `drawCalls` across three backends — a series count, a
series count excluding chrome, and a batch count including chrome. The definition fixed here:
submissions this backend issued to its own drawing API for this frame, chrome included, text
excluded. A backend that genuinely cannot count its own submissions — Core Animation and Shape +
Path both hand a retained graph to a render server that decides submissions on its own thread —
reports `nil`, which is the honest answer, not a proxy count standing in for a different quantity.

**`DeferredTimes` gained `presentedTime: Double?` and a revision tag on each reading.**
`FrameMetrics.rasterNs`'s own documentation says presentation time is one of only two honest
measurements available to a retained-mode backend; `DeferredTimes` had no channel for it. Separately,
Metal's `inFlightFrames = 3` means a raster reading and a GPU reading collected on the same tick can
belong to two different frames — each `RasterTimeReading` now carries the `encodedRevision` it was
produced from, so a caller can tell.

**`suspend()`, `resume()` and `teardown()` are documented as idempotent.** Nothing enforced this
before; a backgrounded-then-foregrounded screen can call `suspend()` or `resume()` twice in a row,
and `teardown()` is called from both a view disappearing and deallocation.

## What is frozen

`ChartRenderer`, `RendererDescriptor`, `EncodeReport`, `DeferredTimes`, and `PreparedFrame` carrying
`chrome: ChromeLayout` and `scale: Double`. Nine conformers have not needed a tenth field, a second
`encode` overload, or an `associatedtype`. A future conformer that finds it needs one of those is
finding a real gap this decision did not anticipate, not failing to fit an existing one — see the
next section.

## What is not frozen, and stays open on purpose

**A renderer's own construction.** `init()` takes no host context today because none of the nine
conformers needed one inside `encode` itself — Metal's compute-heavy work happens on CPU-built
geometry, and its device lives in the view's coordinator, constructed lazily. A future backend that
needs a device, a bundle, or a display scale *before* its first `encode` call is a real gap this
record does not paper over: the honest fix is `init(context:)` carrying exactly what that backend
needs, decided when a conformer actually needs it rather than guessed in advance.

**Whether `encode` can fail.** No conformer built so far has a failure mode `encode` itself needs to
surface — a device-less Metal renderer reports `nil` counters rather than throwing, which has been
sufficient. A backend whose failure is not "I have nothing to report" but "the frame is actively
wrong" would need a typed `throws` this protocol does not have.

**Everything below `encode`.** Geometry representation, buffer strategy, shader source, GPU
resource pooling — each backend's own business, and none of it crosses the boundary this contract
draws. A tenth backend is free to be as different from the ninth as the ninth was from the first.

## Consequence

A change to `ChartRenderer`, `RendererDescriptor`, `EncodeReport`, or `DeferredTimes` after this
date is a breaking change to nine conformers at once, not a card-sized edit to one. The two
deliberately-open items above are not exceptions to the freeze — they are where the next
conformer's actual need, not a prediction of it, gets to shape the protocol.
