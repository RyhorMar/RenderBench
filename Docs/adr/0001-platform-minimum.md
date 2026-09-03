# ADR-0001: One platform minimum for the package, iOS 18

- Status: accepted
- Date: 2026-09-03

## Context

`platforms:` is a property of a package, not of a target. There is no per-target equivalent, so
"the core runs on an older system than the Metal backend" is not expressible in a manifest, and any
plan that assumes otherwise has to be redesigned rather than annotated.

Two forces pull in opposite directions. The demo application wants the newest system, because the
things worth showing — the ProMotion frame range, the newest SwiftUI containers — are there. The
library wants the oldest system it can support, because a charting package that demands the current
major release excludes most of the applications that would otherwise adopt it.

## Decision

The package declares `.iOS(.v18)` and `.macOS(.v15)`. The demo application, which is a separate
Xcode project rather than a SwiftPM product, targets the current release independently.

iOS 18 is the floor because `Mutex` and `Atomic` arrive there, in the `Synchronization` module. The
frame slot is built on `Mutex`: it is the primitive that lets a renderer read the newest snapshot
off the main actor without an isolation hop on the frame path, which is the specific cost the whole
pipeline is arranged to avoid. Below iOS 18 that slot would have to be a lock of our own or an
actor hop, and the second choice would defeat the design.

macOS is present for a narrower reason: the Foundation-only layers then build and test on a CI host
without booting a simulator, which is the fastest failure signal available.

Anything newer than the floor is reached through `@available`, and every such annotation names the
symbol it exists for, in this document. A version raised because "it is newer" is not a decision, it
is a default nobody examined.

## Symbols above the floor

| Symbol | Introduced | Used by | Why nothing older will do |
|---|---|---|---|
| — | — | — | No `@available` annotation exists in the package yet. Rows are added with the code that needs them. |

Availability of standard library additions is checked per symbol rather than assumed from the Swift
version. `Span`, `RawSpan` and `MutableSpan` carry the ABI baseline and are usable at this floor;
`InlineArray` requires iOS 26 and is therefore not used in any layer below the demo.

## Alternatives rejected

**Split into several packages, one per minimum.** Would express the intent exactly: a Foundation-only
core on an old floor, a Metal backend on a new one. Rejected because it multiplies the release
surface — separate tags, separate resolution, cross-package version ranges to keep aligned — for a
project whose entire value is comparing backends against each other in one place. The coupling is
real; splitting it moves the cost from the manifest into every consumer's dependency graph.

**Target the current release throughout.** Simplest, and defensible for an application. Rejected for
the library: it would restrict adoption to the newest systems for the sake of symbols that no layer
below the demo actually uses, and a benchmark nobody can run against their own app is a
demonstration rather than a tool.

**Stay below iOS 18 and hand-roll the lock.** Possible, and the implementation is short. Rejected
because the resulting primitive would have to be trusted without the platform's testing behind it,
on the one path where a correctness mistake shows up as an occasional wrong frame rather than as a
crash — the hardest kind of defect to find and the worst kind to publish.
