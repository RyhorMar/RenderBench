# RenderBench

Nine ways to draw the same realtime chart on iOS, on the same data, with measured frame time
and a documented failure point for each.

**Status: milestone 0 — verifying the build loop.** Nothing renders yet. What exists is the data
path a chart is drawn from: a running-window store, linear and time scales, two downsampling
policies, a frame clock with a one-deep frame slot, and the signal generators the first comparison
needs. None of it has met a compiler yet; the first CI run on this repository is what turns any of
it from written into working.

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
