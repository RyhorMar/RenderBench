# RenderBench

Nine ways to draw the same realtime chart on iOS, on the same data, each reporting what it can
observe about its own cost and saying so when it can observe nothing.

**Status: nine backends of nine, measured once — one run, on one device.** Canvas, Core Animation and
Metal draw through their own device APIs. Swift Charts and Shape + Path are SwiftUI's own retained
view types. Core Image delivers a CPU-rasterised frame through a GPU filter pipeline. SceneKit puts
the chart in a 3D scene, deliberately — its one-pixel line primitive cannot express a stroke width,
and that is a finding, not a bug to work around. A SwiftUI fragment shader recomputes analytic
coverage per pixel. Metal Compute is the one method whose reduction itself runs on the GPU, not the
CPU. Every backend's rasterisation is reported when the method can observe it at all — `nil`, never
a fabricated zero, when it cannot. See [`Docs/adr/0002-renderer-contract.md`](Docs/adr/0002-renderer-contract.md)
for what nine implementations settled about the shared contract, and what is still open on purpose.

Eight of the nine agree with a Core Graphics reference on the same chart, checked on every test
run — but agreement means less for the six that share CoreGraphics as their rasteriser than for the
three that draw through their own pipeline entirely. SceneKit is the ninth and does not agree: a
one-pixel line primitive cannot fill what a 1.5 pt stroke fills, so its test asserts the
disagreement rather than widening a tolerance until it disappears. See
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

The central claim of this project — that these methods differ in measurable ways — **rests on one
run, on one device.** `Benchmarks/results/` holds it: nine backends, three repeats each in its own
process, on an iPhone 16 Pro in Release, with the order randomised and the thermal state nominal at
both ends. What that run does not license is worth as much as what it shows. No confidence
intervals are computed, so it supports "these figures were recorded" and not "this backend is
faster than that one". Every case records `notChecked` for equivalence, so no two backends have
been shown to draw the same picture — and timings are not comparable before the pictures are.
Accessibility and the oil & gas chart types are not written.

```
swift test          # the package's own tests
fastlane ci         # the above, plus the tracked tree's hygiene, the layering rule, the
                    # method pages, the results guard and its own seven cases, and the
                    # demo built and tested
fastlane run_demo   # build, install and launch on a booted simulator
```

The package needs **Swift 6.2 or newer** — the manifest declares that tools version, and every
target builds in Swift 6 language mode. It deploys to iOS 18 and macOS 15; the floor is iOS 18
because the frame slot is built on `Mutex`, and [`Docs/adr/0001-platform-minimum.md`](Docs/adr/0001-platform-minimum.md)
says why that is not negotiable. The two `fastlane` commands additionally need **Xcode 26** — the
demo application targets iOS 26 — plus XcodeGen 2.42 or newer and fastlane itself. Everything above
was last run on Xcode 26.6 with Swift 6.3.3.

## How the methods work, and where they came from

[`Docs/methods/`](Docs/methods/) documents every algorithm in the package on one page per family:
what it does, its contract, why it was chosen over the alternative, the literature it comes from
with a section number, how this implementation differs from that source, and where it lies. Where
a method has no citable origin its page says so, and lists what was consulted and why it does not
qualify, rather than borrowing a reference that does not cover it. Which pages those are is a
column in the index, not a number repeated in prose.

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
Oil & gas chart types and out-of-core data are not started. None of it started before the first
measurement on a device, and that measurement is now in `Benchmarks/results/`.

**Where each method breaks down is not established.** A failure point needs a load ladder — the
same chart at rising point counts until the frame budget is missed — and the one run this
repository holds has a single working point: eight series of 2,512 points. `Capability` is the type
that would carry such a limit, with the device and the date it was measured at; it is declared for
every backend and empty in all nine, which is the honest state rather than a number nobody took.

## Evidence

A number published as a measurement lives in `Benchmarks/results/`, and names the device, the OS
version, the build configuration and the git SHA it came from. That is enforced rather than
observed: bench-guard refuses a file whose SHA is missing, and refuses one taken on a simulator —
Metal is translated there, the thermal envelope does not exist and ProMotion is unavailable.

A handful of numbers appear in comments where the code depends on a system API behaving a
particular way — a display link's actual rate, say. Those name the device they were seen on and
claim nothing beyond it; they are observations, not measurements, and none of them is quoted as a
result.

## Licence

MIT — see [`LICENSE`](LICENSE).
