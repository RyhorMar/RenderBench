# RenderBench

Nine ways to draw the same realtime chart on iOS, on the same data, with measured frame time
and a documented failure point for each.

**Status: three backends of nine, and no measurement on a device yet.** Canvas draws a live strip
chart from a running window, with min/max and LTTB selectable at runtime and an overlay reporting
frame-time percentiles. Core Animation draws the same frame as a layer tree. Metal uploads the
points once and expands them into triangles in a vertex shader, and is the only one of the three
whose rasterisation is measured rather than inferred: a command buffer carries its own timestamps.

The three agree on what they draw, checked on every test run — but agreement is a weaker claim for
the first two, which share a rasteriser, than for the third, which does not. See
[`Docs/methods/equivalence.md`](Docs/methods/equivalence.md).

The central claim of this project — that these methods differ in measurable ways — **is not yet
supported by a single measurement on hardware.** `Benchmarks/results/` is empty on purpose: the
guard in `fastlane bench_guard` rejects a run made in a simulator, in Debug, or on a thermally
throttled device, and no run has been made that passes it. The remaining six backends,
accessibility and the oil & gas chart types are not written.

```
swift test          # the package: 215 tests
fastlane ci         # package, tests, layering rule, demo build
fastlane run_demo   # build, install and launch on a booted simulator
```

## How the methods work, and where they came from

[`Docs/methods/`](Docs/methods/) documents every algorithm in the package on one page per family:
what it does, its contract, why it was chosen over the alternative, the literature it comes from
with a section number, how this implementation differs from that source, and where it lies. Three
of the methods have no citable origin and say so on their own pages rather than borrowing a
reference that does not cover them.

Every reference was fetched before it was written down. `fastlane method_docs` fails when a page
names a symbol the code no longer declares.

The demo's Xcode project is generated from `Demo/project.yml` by XcodeGen and is not committed:
SwiftPM has no product type for an iOS application, but a checked-in project file merges badly and
drifts from the manifest unnoticed.

## What this does NOT do (yet)

Metal rendering, the other eight backends, downsampling, axes, interaction, accessibility,
oil & gas chart types, out-of-core data, printing. Each is added only after the previous slice
builds green and is measured on a device.

## Evidence

Every performance claim in this repository names the device, the OS version, the build
configuration and the git SHA it came from, and the raw run is checked in under
`Benchmarks/results/`. Simulator timings are never published: Metal is translated there, the
thermal envelope does not exist and ProMotion is unavailable. A number without a run behind it
is labelled a hypothesis, in this README and in the comparison matrix alike.
