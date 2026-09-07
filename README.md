# RenderBench

Nine ways to draw the same realtime chart on iOS, on the same data, with measured frame time
and a documented failure point for each.

**Status: nine backends of nine, and none measured on a device yet.** Canvas, Core Animation and
Metal draw through their own device APIs. Swift Charts and Shape + Path are SwiftUI's own retained
view types. Core Image delivers a CPU-rasterised frame through a GPU filter pipeline. SceneKit puts
the chart in a 3D scene, deliberately — its one-pixel line primitive cannot express a stroke width,
and that is a finding, not a bug to work around. A SwiftUI fragment shader recomputes analytic
coverage per pixel. Metal Compute is the one method whose reduction itself runs on the GPU, not the
CPU. Every backend's rasterisation is reported when the method can observe it at all — `nil`, never
a fabricated zero, when it cannot. See [`Docs/adr/0002-renderer-contract.md`](Docs/adr/0002-renderer-contract.md)
for what nine implementations settled about the shared contract, and what is still open on purpose.

Each backend agrees with a Core Graphics reference on the same chart, checked on every test run —
but agreement means less for the six that share CoreGraphics as their rasteriser than for the three
that draw through their own pipeline entirely. See
[`Docs/methods/equivalence.md`](Docs/methods/equivalence.md).

Every method also lives behind its own screen in the demo application, pushed and popped through
real navigation rather than switched in place — the one place these nine differ more than they do
in frame time. A screen's GPU-owning renderer is torn down when its route leaves the navigation
path, not when its view happens to disappear or deallocate: `onDisappear` also fires when a sheet
merely covers a still-live screen, and `deinit` on iOS can arrive on the next run of `body` rather
than at the moment a screen is popped. Verified for all nine with a `weak`-reference probe and,
separately, with a UI test driving real navigation and a real background/foreground cycle — not
proof that no backend can leak under adversarial timing, which needs a device and Instruments to
settle and is recorded as open rather than assumed closed.

The central claim of this project — that these methods differ in measurable ways — **is not yet
supported by a single measurement on hardware.** `Benchmarks/results/` is empty on purpose: the
guard in `fastlane bench_guard` rejects a run made in a simulator, in Debug, or on a thermally
throttled device, and no run has been made that passes it. Accessibility and the oil & gas chart
types are not written.

```
swift test          # the package: 342 tests
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

All nine backends draw the one reference chart RC-1, and only four of its fifteen required
properties — thick smoothed line (partially), min/max downsampling, null gaps, and the categorical
palette. Not built for any backend: crossover fill, an uncertainty band, a log axis, a second Y
axis, annotations, a synchronised cursor, zoom/pan, delta-loading into a GPU buffer, accessibility,
a data-age indicator. Every one of those is added once, across all nine backends at once, rather
than per backend — see [`Docs/adr/0002-renderer-contract.md`](Docs/adr/0002-renderer-contract.md).
Oil & gas chart types and out-of-core data are not started. None of it starts before the first
measurement on a device.

## Evidence

Every performance claim in this repository names the device, the OS version, the build
configuration and the git SHA it came from, and the raw run is checked in under
`Benchmarks/results/`. Simulator timings are never published: Metal is translated there, the
thermal envelope does not exist and ProMotion is unavailable. A number without a run behind it
is labelled a hypothesis, in this README and in the comparison matrix alike.

## Licence

MIT — see [`LICENSE`](LICENSE).
