# Buffers and windows

## What it does

Holds the most recent samples of a running series, and locates the sub-range of them that a moving
window covers, without copying either.

## Where it lives

| Symbol | Module |
|---|---|
| `RingBuffer` | `BenchCore` |
| `NullMask` | `BenchCore` |
| `DataSeries` | `BenchCore` |
| `CarrierSearch` | `BenchCore` |
| `SeriesSlice` | `BenchCore` |

## Contract

- `RingBuffer` retains the newest `capacity` elements and exposes them **as one contiguous run**,
  whatever the head position. `push` is O(1) with no allocation after construction.
- Carriers, values and gaps are three parallel rings, pushed together and rotating together.
- `CarrierSearch.indices(of:within:)` returns the half-open index range covered by an inclusive
  carrier window, in O(log *n*), by binary search on both ends.
- A borrowed `SeriesSlice` **must not outlive the closure it is handed to**. The buffers point into
  storage the provider is free to reuse as soon as the closure returns.

## Why this method

**Mirrored storage.** The buffer allocates `2 × capacity` slots and writes every element twice, at
`i` and at `i + capacity`. The duplicate costs memory a plain ring would not, and buys the property
the renderers need: the retained elements are contiguous for any head position, so a frame hands the
GPU a single pointer instead of two slices that must be stitched or copied on the hot path.

**Three parallel rings, not one ring of structs.** A renderer uploads carriers and values as two
contiguous runs without restriding, and a gap cannot drift away from the sample it belongs to.

**Binary search on both ends rather than a filter.** The window moves every frame and the series does
not, so locating it must not cost anything proportional to the series length. The upper bound uses
`nextUp` on the window's top rather than a second comparison mode, which turns an inclusive range
into the half-open bound a slice needs with one search shape instead of two.

**Gaps as runs, not flags.** Both consumers want the same thing: a renderer lifts the pen between
runs, a downsampler refuses to let a bucket span one. Exposing runs rather than per-position flags
means the two cannot disagree about where a line breaks.

## Provenance

**The mirrored ring buffer has no citable origin.** It is a well-travelled technique with several
independent names — "magic ring buffer", "mirrored buffer", and in its virtual-memory form the
double-mapped circular buffer — and no publication this project can point to as its source. What was
consulted: Cooke's bip-buffer write-up, which solves the same contiguity problem with a different
structure (two regions rather than a mirror) and is not this; and the virtual-memory variant, which
maps one physical region twice and is not this either, since this copies rather than maps. Recorded
as folklore, because it is.

**Binary search.** Knuth, D. E. *The Art of Computer Programming, Volume 3: Sorting and Searching*,
2nd edition, Addison-Wesley, 1998, §6.2.1 — the algorithm and, more to the point, the discussion of
how often its boundary conditions are got wrong. Cited from the book rather than from a URL; no
online copy was fetched, and this page does not pretend one was.

## How this implementation differs from the source

- The mirror is maintained by **writing twice**, not by mapping one physical page range at two
  virtual addresses. Double-mapping costs no memory and needs page-aligned capacities, a
  platform-specific mapping call and an unsafe deallocation path; writing twice costs one extra store
  per push and stays inside safe Swift. This is a trade this project made deliberately and has not
  measured.
- `NullMask` stores one `Bool` per position rather than packed bits. The packed form is a real
  optimisation; nothing here has been measured yet, and an unmeasured optimisation in a project about
  measurement would be the wrong kind of irony. The representation is private, so packing it later
  changes no caller.

## What it costs and where it lies

- Twice the memory for every ring. At 5 kHz over a ten-second window that is 50 000 doubles per
  series held as 100 000 — 800 KB per series rather than 400 KB.
- `RingBuffer` needs a placeholder value at construction, because the mirrored layout requires random
  access and so rules out growing the storage on demand. The placeholder is never observable.
- The borrow is enforced by convention, not by the compiler. A `SeriesSlice` that escapes its closure
  is undefined behaviour rather than a style violation. Non-escapable types with lifetime
  dependencies would express this properly and are not used here yet.
- `DataSeries.append` asserts monotonically increasing carriers in debug builds only. In release, an
  out-of-order series produces silently wrong windows rather than a diagnostic.

## Verified by

`RingBufferTests`, `NullMaskTests`, `DataSeriesTests`, `SeriesCollectionProviderTests`,
`ArrayProviderTests` in `BenchCoreTests`: the snapshot stays contiguous at every head position; a
model test agrees with a reference array over 10⁴ deterministic operations; segment count equals the
number of uninterrupted stretches; the mask rotates with the data it describes; windowing is correct
after the ring has wrapped; the shared carrier search agrees with a linear scan over a grid of
windows; a dropout reaches the renderer as a gap rather than a value.
