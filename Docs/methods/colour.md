# Colour

## What it does

Holds the project's colours in a space where interpolating two of them does not pass through a muddy
band: eight for series, and three for the rasteriser families the backends fall into. The two sets
carry different weight. The three families are separable under simulated colour vision deficiency,
measured; the eight series are not, also measured — so a series colour is a viewing aid and its
label is what identifies it.

## Where it lives

| Symbol | Module |
|---|---|
| `PaletteColor` | `BenchCore` |
| `Palette` | `BenchCore` |
| `RasteriserFamily` | `BenchCore` |

## Contract

- `PaletteColor` holds **linear** sRGB components in `0...1`, not gamma-encoded ones.
- `PaletteColor(srgb:_:_:)` converts an 8-bit gamma-encoded triple to linear on construction.
- Eight categorical colours, in a light and a dark variant. Beyond eight, `colour(forSeries:dark:)`
  cycles — deliberately, as a signal: a chart that reaches it should be labelling series directly.
- Three family colours, one set for both themes, from `colour(for:)`. They are published as 8-bit
  sRGB triples fixed in the source, not derived at run time from the `oklch` coordinates the search
  ran in.
- Neither set identifies anything on its own. A series is identified by its label, a family by its
  name; colour duplicates the distinction and never carries it alone.
- The core holds no platform colour type. Conversion to a rendering colour happens in the backend.

## Why this method

**Linear rather than encoded.** The sRGB encoding is a transfer function, not a scale: averaging two
encoded values does not produce the colour halfway between them. Any interpolation — a gradient, a
blend, an antialiased edge — has to happen in linear light or it darkens through the middle.

**Categorical, not sequential.** Series in a strip chart have no natural order, so a ramp would imply
one that does not exist.

**Eight is the limit on purpose.** Beyond eight, colour stops identifying anything; the honest
alternative is a direct label on each series, not a ninth hue.

**Red and green are not paired as the first two.** The most common deficiency makes exactly that
pair the hardest, and it is the pair most default palettes open with.

**Three families, not nine methods.** Colour was going to identify each of the nine backends, and
measurement closed that off: at the floor this page sets — ΔE2000 of at least 15 after Machado's
simulation — the largest set that fits inside the sRGB gamut and clears 3:1 against the project's
surfaces is **seven** colours for one theme with lightness free, and **three** once one set has to
serve both themes. Nine and eight are unreachable at any lightness. Lowering the floor to 10 would have let
nine in; that is choosing the criterion to fit the answer, which `equivalence.md` refuses for the
equivalence threshold and this page refuses for the same reason.

Three is also the distinction the benchmark actually measures — which code turns geometry into
pixels — so the colours carry the rasteriser's lineage and the method's identity stays with its
name and number.

**Published as sRGB hex, `oklch` only as origin.** The search runs in `oklch`, where equal lightness
is expressible; the result ships as 8-bit triples. A colour whose `oklch` coordinates fall outside
the sRGB gamut is clamped channel by channel on the way in, and a clamped colour is a different
colour from the one named — a set stated in `oklch` can therefore claim a separation the pixels do
not have.

## Provenance

**The sRGB transfer function.** IEC 61966-2-1:1999, *Multimedia systems and equipment — Colour
measurement and management — Part 2-1: Colour management — Default RGB colour space — sRGB.*
<https://webstore.iec.ch/publication/6169> — retrieved and verified (the standard's title and number
confirmed on the publisher's page; the text itself is paywalled and was not read). The piecewise
conversion implemented here — linear below 0.04045, a 2.4 power above it — is that standard's.

**Colour vision deficiency and categorical palettes.** Okabe, M., Ito, K. *Color Universal Design:
How to make figures and presentations that are friendly to colorblind people.* <https://jfly.uni-koeln.de/color/>
— retrieved and verified. The source of the principle applied here: choose hues that remain separable
under deuteranopia and protanopia, and do not rely on red-versus-green.

**Simulating a deficiency, for verification.** Machado, G. M., Oliveira, M. M., Fernandes, L. A. F.
*A Physiologically-based Model for Simulation of Color Vision Deficiency.* IEEE Transactions on
Visualization and Computer Graphics 15(6), 2009, pp. 1291–1298. DOI
[10.1109/TVCG.2009.113](https://doi.org/10.1109/TVCG.2009.113) — metadata retrieved and verified
through Crossref.

**Measuring the resulting difference.** Sharma, G., Wu, W., Dalal, E. N. *The CIEDE2000
color-difference formula: implementation notes, supplementary test data, and mathematical
observations.* Color Research & Application 30(1), pp. 21–30. DOI
[10.1002/col.20070](https://doi.org/10.1002/col.20070) — metadata retrieved and verified through
Crossref, which records the online date as 2004; the journal issue is dated February 2005.

## How this implementation differs from the source

- The eight hues are **not** Okabe and Ito's set. They were chosen by eye against this project's two
  backgrounds, following the same principle — and following a principle turned out not to be the
  same as satisfying it: see below.
- **The check is implemented, and outside this package.** Machado's model and CIEDE2000 were
  implemented to decide the family colours and to measure the series set; that implementation is a
  design tool and is not part of the package or its test suite. What the tests here pin is the
  outcome — the exact triples the measurement accepted — so a colour cannot drift away from the
  figures below unnoticed. What they cannot do is re-derive those figures.

## What it costs and where it lies

- **"CVD-safe" was inherited, and measurement refuted it for the series set.** Simulated with
  Machado's model and compared by CIEDE2000, the worst pair among the eight light colours is
  **3.3** (series 6 and 8) and among the eight dark ones **0.2** — series 1 and 5 under
  deuteranopia, effectively the same colour — against a floor of 15. It is not one bad pair either:
  12 of the light set's 28 pairs fall below the floor, and 15 of the dark set's. This cannot be
  repaired by picking different colours: eight does not fit at that floor. What follows is not a
  better palette but a demotion — series colour is a viewing aid, and the label beside a line is
  required rather than recommended.
- **The family set does clear the floor, and the guarantee is still narrow.** Worst pair 17.2 under
  deuteranopia, 21.0 under protanopia, 17.3 under tritanopia, 47.5 for normal vision; each colour
  clears 3:1 against all eleven surfaces of the two themes, the tightest being 3.12:1. That holds
  for the deficiencies Machado's model covers, at the severity measured, on those surfaces — not for
  every reader.
- **Rounding to 8 bits costs 0.1 of the worst pair:** 17.3 in `oklch`, 17.2 after the triples are
  rounded. The figures quoted are the ones measured on the rounded values, because those are the
  values that ship.
- The dark variant of the series set is a hand-lifted version of the light one, not a re-derivation.
  Its contrast against a dark ground has not been measured either.
- Cycling past eight silently reuses a hue. That is visible on a chart with nine series and is not
  reported anywhere in the API.
- Linear components are stored as `Double` per channel — three times the memory of an 8-bit triple,
  for a value that exists once per series. Deliberate: the conversion is done once at construction
  rather than per frame.

## Verified by

`PaletteTests` in `BenchCoreTests`: the encoded-to-linear conversion matches the standard at black,
white and mid-grey — 50 % encoded sRGB is 21.6 % linear light, and getting that wrong is what makes
a naive gradient darken through the middle; the transfer function is continuous across its
piecewise join and monotonic over all 256 levels; the channels are independent; each variant holds
eight distinct colours; no pair has collapsed towards another in linear space; the two variants
differ at every index; indices wrap rather than trap, including negative ones, which Swift's
signed `%` would otherwise send out of bounds.

The family set: the three triples are pinned to their published values, written out in the test
rather than read back from the palette; each family has its own colour; and the three sit at the
same lightness, computed from the standard's luminance weights, so a set that drifted lighter or
darker in one family fails even if it stayed distinguishable.

Mutation-checked: replacing the palette with a single colour, dropping the transfer function,
substituting a plain 2.2 gamma for the piecewise curve, using `abs()` instead of a floored modulo,
and collapsing the three channels onto one each fail at least two tests. Every single channel of
every family colour was mutated by one 8-bit step, in all nine positions, and each was caught;
so were giving two families the same colour and lightening one of them.

**Separability itself is not tested here, and no longer needs to be claimed here.** The measurement
that produced the figures above ran outside this package, and what the tests hold is that the
colours which passed it are the colours that ship.
