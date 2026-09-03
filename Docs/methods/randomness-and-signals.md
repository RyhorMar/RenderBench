# Randomness and signals

## What it does

Produces the synthetic series every measurement in this package runs against. One seed produces one
bit-identical stream, on every launch and every platform — a benchmark whose input differs between
runs cannot support a claim about a difference between runs.

## Where it lives

| Symbol | Module |
|---|---|
| `SplitMix64` | `BenchGenerators` |
| `GaussianNoise` | `BenchGenerators` |
| `SignalStream` | `BenchGenerators` |
| `Signal` | `BenchGenerators` |
| `OscillatingReaction` | `BenchGenerators` |
| `ModulatedCarrier` | `BenchGenerators` |

## Contract

- **Determinism is the contract.** `SystemRandomNumberGenerator` is unusable here: it is seeded from
  the system and cannot be replayed.
- `SignalStream` keeps its place across calls, so sample *n* is the same number no matter how many
  calls it took to reach it. Asking for a count already reached produces nothing.
- One stream per series, each with its own seed. Sharing a generator across series correlates their
  noise.
- Signals are pure functions of time plus additive noise; with `noiseSigma == 0` a signal is exactly
  the formula in its own documentation.

## Why this method

**SplitMix64 rather than the system generator, and written out rather than imported.** It is small
enough to read in one sitting, has no dependencies, and produces the same stream on any platform —
which a system generator explicitly does not promise.

**Box–Muller rather than a library transform.** Same reason: the transform must be reproducible
across platforms, and it produces two normal deviates per pair of uniforms, so the second is kept
rather than discarded.

**Two signals, each kept for one defect it exposes.** A damped oscillation on a slow drift is the
well-behaved case everything should render correctly — the baseline the others are read against. A
400 Hz carrier under a 3 Hz modulation is chosen so that one pixel column of a ten-second window on
a 400-point axis spans ten carrier periods: the width at which a policy that picks representative
samples flattens the envelope and one that reports extrema does not. A signal that reveals nothing
is data volume, and data volume is not a test.

## Provenance

**SplitMix64.** Steele, G. L., Lea, D., Flood, C. H. *Fast splittable pseudorandom number
generators.* OOPSLA 2014, pp. 453–472. DOI
[10.1145/2660193.2660195](https://doi.org/10.1145/2660193.2660195) — metadata retrieved and verified
through Crossref (the publisher serves a bot challenge to direct retrieval). The mixing function and
its three constants — the golden-ratio increment and the two multipliers — are the paper's.

**Box–Muller.** Box, G. E. P., Muller, M. E. *A Note on the Generation of Random Normal Deviates.*
The Annals of Mathematical Statistics 29(2), 1958, pp. 610–611. DOI
[10.1214/aoms/1177706645](https://doi.org/10.1214/aoms/1177706645) — metadata retrieved and verified
through Crossref. Two pages; the entire method is in them.

**The signal models have no source and need none.** A damped sinusoid on a linear drift and a
modulated carrier are textbook forms, not results. Their *parameters* — decay, frequencies,
modulation depth, noise sigma — were chosen so that the second signal aliases at the axis width this
package draws at, which is an engineering choice this project made and states here rather than
implying it came from somewhere.

## How this implementation differs from the source

- **SplitMix64: no splitting.** The paper's contribution is a generator that can be split into
  independent streams; this uses only the sequential `nextLong` mixing function. Independence between
  series is obtained by separate seeds, which is weaker than the paper's construction and sufficient
  for eight series of display noise.
- **Box–Muller: zero is excluded from the first uniform** before the logarithm. The paper does not
  discuss the degenerate draw because it predates the floating-point representation that makes it
  reachable.
- The polar form of Box–Muller — usually faster, since it avoids the trigonometry — is not used. The
  rejection loop it needs makes the number of underlying draws per output vary, which would make a
  stream's position depend on rejected values.

## What it costs and where it lies

- SplitMix64 is not cryptographically secure and is not intended to be. It has a fixed 64-bit state
  and a period of 2⁶⁴.
- The noise is independent per sample: white, with no spectral shaping. Real instrument noise is not.
  A 1/f generator is specified for this project and not implemented, so any claim about behaviour
  under realistic noise is currently untested.
- Seeds are constants in the source rather than derived, so two series with adjacent seeds have
  adjacent SplitMix64 states. The mixing function makes that unobservable in practice; it has not
  been measured here.

## Verified by

`SplitMix64Tests`, `SignalTests`, `SignalStreamTests` in `BenchGeneratorsTests`: one seed produces
one bit-identical stream; zero is a usable seed; the noiseless signal matches the closed form
evaluated independently in the test; the Gaussian draw is centred with unit variance over 10⁵
samples; a stream's output is independent of how the advance is split into calls; separate seeds do
not correlate; the carrier's envelope spans the full amplitude within one window.
