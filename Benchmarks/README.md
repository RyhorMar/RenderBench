# Benchmarks

**A measurement taken on a simulator is not a measurement.** Metal is translated there, there is no
thermal envelope, the display is not the device's, and the CPU is a desktop one. Nothing measured on
a simulator is stored in this directory, and `bench-guard` refuses a file that says it was.

## What is in here

| Path | What it is |
|---|---|
| `schema.json` | the format of a run, with every required field and why it is required |
| `example.json` | the shape of a run, with **invented numbers**. Its `run.id` is `example`, which keeps it out of `results/` and out of any table |
| `results/` | measured runs, one file per device, OS and commit |

`example.json` is generated from the same Swift model the runner writes, by
`swift run CheckBenchmarkResults . --write-example`. It is not hand-maintained, so it cannot drift
into describing a format that no longer exists.

## Procedure for one case

1. **Warm up 120 frames and discard them.** The first frames of a run pay for allocation, first-time
   texture upload and a cold cache; including them measures the launch, not the drawing.
2. **Measure 1200 frames.** Ten seconds at 120 Hz, twenty at 60.
3. **Cool down 20 seconds** and re-check the thermal state before the next case.
4. **Repeat three times, restarting the application between repeats.** A repeat that reuses a warm
   process measures the process, not the code.
5. **Randomise the order of backends within a chart type**, and record the order used. Measuring
   backends in a fixed order lets thermal drift accumulate into whichever one goes last.

## Preconditions, and who enforces them

Every one of these is a way a run can be quietly wrong, so each is a hard stop rather than a
warning. They are enforced **at both ends**: the runner refuses to start when they do not hold, and
`bench-guard` refuses to store a file that says they did not. A methodology enforced at one end only
is enforced nowhere — and a document listing preconditions that nothing checks is worse than no
document, because it reads as a guarantee.

Checked by `bench-guard` on every stored file: not a simulator, Release configuration, thermal state
below serious at **both** ends of the run, Low Power Mode off, battery at or above 40 % when the
platform reports one, and no case whose equivalence check failed.

Two more, and they are there because a correctly shaped file is not the same thing as a
measurement. The application can write one from whatever happens to be on screen — a button, no
warm-up, one pass — and every field in it is honest: `warmupFrames` really is 0, and there really
is one repeat. So a stored file must also discard warm-up frames in every case and contain all
three repeats. Neither rule reaches outside `results/`: `example.json` has one repeat by design.

The rest are the runner's to enforce, because only it is present while the run happens:

- not a simulator;
- Release configuration — a Debug run measures the compiler's bookkeeping;
- Low Power Mode off;
- `thermalState == .nominal`, waiting up to five minutes for it;
- battery above 40 %;
- debugger detached;
- aeroplane mode, fixed brightness, auto-lock off;
- for a 120 Hz run: `maximumFramesPerSecond == 120`, `CADisableMinimumFrameDurationOnPhone` in the
  Info.plist, **and** an explicit `preferredFrameRateRange` on the display link. Any one of the
  three missing caps the link at 60, and every "120 Hz" number in the file is then a 60 Hz number.
  This is not hypothetical: the app shipped with the key misspelled — the trailing `OnPhone` is
  part of it, and an unrecognised key is ignored in silence — and ran at 60 Hz for its whole life
  before a device measured it. `maximumFramesPerSecond` does not catch that on its own: it reports
  what the display can do, not what the app is getting.

## What is published, and what is refused

Published: nearest-rank p50, p95, p99 and max in three separate columns — `cpu` for preparation
and geometry building, `raster` for the backend's own drawing, `gpu` for GPU execution — plus the
missed-deadline ratio and the full environment.

**The three are never added together into one frame time.** A backend that reports no `raster` and
no `gpu` has not been measured as a rendering method: its drawing happened somewhere this process
cannot see. Reading its `cpu` column as a frame cost is the mistake this format exists to prevent.

**Refused as a comparison** unless all three hold: the equivalence check passed, `pointsDrawn`
agrees between the two backends, and the confidence intervals on p95 do not overlap. Absent those,
the honest phrasing is "A gives a lower frame time at the cost of X", with X named. A backend that
quietly dropped points or lowered its antialiasing wins any benchmark, which is why timings are not
compared before the pictures are.

**Regression** means the new interval does not overlap the baseline's **and** the effect is at least
10 %. Everything else is noise, and calling it a regression trains everyone to ignore the check.

## What is not measured

Stated because a list of gaps is worth more than ten more numbers:

- **Energy.** Not measured at all. A backend that wins on frame time may lose on battery, and this
  says nothing about it.
- **First-frame latency.** Every number here is steady state.
- **Behaviour under memory pressure.** No jetsam or memory-warning case exists.
- **Confidence intervals.** The procedure above specifies bootstrap intervals on p95; the code does
  not compute them yet. Until it does, no file in `results/` supports a claim that one backend is
  faster than another — only that it recorded lower numbers in one run.
- **Equivalence.** The check is specified and not implemented. Every case currently records
  `notChecked`, which is a distinct value from `passed` precisely so it cannot be read as one.
- **GPU time.** No GPU backend exists yet, so every `gpu` block is absent rather than zero.

## Reading a file

Nothing in a stored file needs interpretation except this: `pointsSubmitted` versus `pointsDrawn`.
When they differ, the backend drew less than it was given, and its frame time was bought with work
it did not do. Compare those two before comparing any duration.
