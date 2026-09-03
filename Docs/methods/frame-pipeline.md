# Frame pipeline

## What it does

Decides when a frame happens, what data it draws, and what to do when the producer runs faster than
the renderer. Three independent rates meet here: the source producing samples, the display asking
for frames, and the renderer consuming them.

## Where it lives

| Symbol | Module |
|---|---|
| `FrameClock` | `BenchRuntime` |
| `DisplayTicking` | `BenchRuntime` |
| `DisplayLinkTicker` | `BenchRuntime` |
| `FrameSlot` | `BenchRuntime` |
| `FrameSnapshot` | `BenchRuntime` |
| `SlotCounters` | `BenchRuntime` |

## Contract

- **One clock per scene, never one per chart.** Every observer of one clock sees the same frame
  number for the same tick.
- Advancing the clock is not on its public surface. Only the tick source can do it; drawing code has
  no way to reach it.
- Observers are called in **registration order**, taken as a snapshot before the fan-out, so
  unsubscribing from inside a callback is safe and the order does not vary between launches.
- A subscription token is **not discardable**: a caller who drops it can never unsubscribe.
- `FrameSlot` holds **one** snapshot. Publishing over an untaken one counts a drop.
- A snapshot from a superseded `epoch` is discarded and counted, never drawn.
- The slot's contents and its counters live under **one** lock, so `counters` is a consistent
  snapshot of what the slot did.

## Why this method

**One tick per scene.** Two renderers each running their own display link drift apart within
seconds: their cursors disagree, their windows show different instants, and a comparison between
them stops meaning anything. Since comparison is the entire point of this package, the clock is a
property of the scene and not of a view.

**A one-deep slot rather than a queue.** A renderer that falls behind wants the current state of the
world, not a backlog of stale ones. Buffering deeper trades latency for completeness in the wrong
direction for a live chart.

**The drop counter is what makes it honest.** The same structure without it is what people call
back-pressure when it is nothing of the sort: back-pressure slows the producer down; this does not,
it records how often it did not. A lossless record, when one is needed, is a second channel, not a
deeper queue here.

**Epochs.** Changing the window, the series set or the downsampling policy makes a prepared snapshot
correct data answering a question nobody is asking. Drawing it produces one frame of the previous
configuration inside the new one — a flicker that is very hard to attribute after the fact.

## Provenance

**None of this has an authoritative source, and this page will not manufacture one.**

What was consulted, and why none of it is a citation for the design:

- Apple's `CADisplayLink` documentation, <https://developer.apple.com/documentation/QuartzCore/CADisplayLink>
  — retrieved and verified (iOS 3.1+, macOS 14.0+). It defines the timestamps this code consumes;
  it says nothing about how to structure a pipeline around them.
- Triple buffering as described in vendor GPU guidance. Related in spirit — bounded buffering to
  decouple producer from consumer — but it is a resource-reuse pattern for command submission, not a
  latest-value slot, and this package does not implement it yet.
- The general producer–consumer literature. The one-deep lossy slot is a folk pattern with many
  names and no canonical treatment worth citing at this code.

The design here is the result of one specific critique of an earlier draft — that `AsyncStream` was
being used as though it were a multi-consumer subscription, that `bufferingNewest(1)` was being
called back-pressure, and that the frame tick was being taken from inside the drawing code. That
critique is the actual provenance, and it is recorded in this project's decision log rather than in
a bibliography.

## How this implementation differs from the source

Not applicable: there is no source. The nearest thing to a reference implementation is the display
link contract, and this uses it as documented.

## What it costs and where it lies

- **The demo publishes and takes in the same synchronous call**, so its drop counter is structurally
  always zero and its stale-epoch counter can never fire. The mechanism is sound; the current
  producer is not separated from the consumer, so the overlay's "dropped" row reports a property of
  the wiring rather than of the load. This will remain true until a backend produces off the main
  actor.
- A one-deep slot cannot distinguish "the renderer is one frame behind" from "the renderer stopped".
  The counters make the aggregate visible; a single frame's fate is not recoverable.
- `DisplayLinkTicker` exists only on iOS. On macOS the package builds without a tick source, so
  everything above it is exercised in tests through a hand-driven ticker and never against a real
  display on that platform.
- `FrameClock` is main-actor bound because every real source delivers there. A future backend that
  wants to prepare frames off the main actor will need the slot, which is already `Sendable`, and not
  the clock.

## Verified by

`FrameClockTests`, `FrameSlotTests` in `BenchRuntimeTests`: two consumers see the same frame number;
frame numbers are assigned by the clock, not by the source; the source starts on the first observer
and stops after the last; observers are called in registration order; unsubscribing from inside a
callback is safe; overwriting an untaken snapshot is counted as a drop; a snapshot from a superseded
configuration is discarded rather than drawn.
