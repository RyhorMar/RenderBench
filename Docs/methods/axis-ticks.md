# Axis ticks

## What it does

Chooses where an axis is labelled and what the labels read, so that a reader can subtract two of
them in their head and so that they do not overlap. Two ladders are used: decimal steps for
quantities, clock divisions for time.

## Where it lives

| Symbol | Module |
|---|---|
| `NiceSteps` | `BenchScales` |
| `TickLayout` | `BenchScales` |
| `AxisOrientation` | `BenchScales` |
| `TextMeasuring` | `BenchScales` |
| `LinearScale` | `BenchScales` |
| `TimeScale` | `BenchScales` |

## Contract

```swift
func ticks(
    target: Int,
    axisLength: Double,
    orientation: AxisOrientation,
    measuring: some TextMeasuring
) -> [Tick]
```

- **`target` is a cap, not a wish.** At most that many ticks are returned. A caller sizing a label
  pool from it must not be handed one more.
- **`axisLength` is required.** Collision avoidance is arithmetic on a measured label against
  available length; without the length the measurer is decoration.
- **`orientation` selects which dimension of a label limits spacing** — width on a horizontal axis,
  line height on a vertical one. One measurement cannot answer both.
- **Ticks are ordered by increasing value and lie inside the domain.**
- A collapsed or unlabelable domain returns no ticks rather than trapping.

## Why this method

**Decimal steps snap to 1, 2, 2.5 or 5 times a power of ten.** Axis labels are read, subtracted and
interpolated by eye; a step of 3.7 defeats all three. The 2.5 is what makes quarters land on round
numbers, which matters for fractions and percentages.

**Time does not use that ladder.** Clock divisions are not decimal — 2.5 minutes is not a boundary
any reader recognises — so time steps come from a closed list running from a tenth of a second to a
day. The list starts below a second because the reference chart's shortest window is one second; a
one-second floor gives that window two labels, which is an axis with endpoints rather than an axis.

**Label precision is derived from the step, not from the values.** That is what keeps label width
stable while a window scrolls, and it is why a step of 2.5 carries one more decimal than its
magnitude alone suggests.

## Provenance

**Nice numbers.** Heckbert, P. *Nice Numbers for Graph Labels.* In *Graphics Gems*, Academic Press,
1990, pp. 61–63. The reference implementation `label.c` carries that attribution in its own header
and is archived at <https://github.com/erich666/GraphicsGems> — retrieved and verified, including
the file header naming the author, the book and the year.

**The clock ladder has no authoritative source.** It is the set of divisions that appear on clocks
and on every charting library's time axis, arrived at by convention rather than by publication. What
was consulted: Heckbert's method (decimal, does not apply), and the axis behaviour of established
plotting libraries (convergent, but conventions are not citations). Recorded as folklore rather than
dressed up with a reference that does not say what it would need to say.

**Label collision.** No source. The rule here — spacing must exceed the measured extent of the
widest label times 1.5 — is a gutter chosen by eye, not a perceptual result. The 1.5 is a constant
this project has not measured and does not defend beyond "labels that merely abut are unreadable".

## How this implementation differs from the source

- Heckbert's `nicenum` chooses from 1, 2, 5, 10; this adds **2.5**, which the original omits.
- Heckbert's routine sizes an axis for a given tick count; this **also fits the count to the axis**,
  by measuring the labels the caller's target would produce and reducing the count until they fit.
- **Both ends of the domain are measured**, not the upper bound alone. A domain like `-100000...1`
  has its longest label at the bottom, and under-measurement is always the failing direction because
  the fitted count can only reduce the caller's target.

## What it costs and where it lies

- The number of labels changes in steps as the window zooms, because the ladder does. It does not
  change by one at a time. Smooth label counts across a zoom require hysteresis on the domain, which
  is specified for this project and not implemented; until it is, the label count on a continuously
  zooming axis will jump when the step changes rung.
- Text width is estimated arithmetically — a constant per character — rather than laid out. For a
  monospaced-digit font that is within a point; for anything proportional it is not. The measurer is
  behind a protocol so a caller who needs exactness can supply it.
- A time domain beyond roughly 4×10¹⁸ seconds cannot be labelled and returns an empty axis. A caller
  charting nanosecond-epoch values has made a unit mistake, and a crash is not how they should find
  out.

## Verified by

`AxisScaleContractTests`, `LinearScaleTests`, `TimeScaleTests` in `BenchScalesTests`: map stays in
the unit interval and round-trips for every scale; the tick count never exceeds the target; ticks are
ordered and inside the domain; a vertical axis fits more labels than a horizontal one of equal
length; the widest label is measured from both domain ends; every time step comes from the ladder; a
one-second window is labelled in tenths; a domain too large to label yields no ticks instead of
trapping.
