# Colour

## What it does

Assigns a colour to each series, in a space where interpolating two of them does not pass through a
muddy band, using a set chosen to stay distinguishable for readers with the common forms of colour
vision deficiency.

## Where it lives

| Symbol | Module |
|---|---|
| `PaletteColor` | `BenchCore` |
| `Palette` | `BenchCore` |

## Contract

- `PaletteColor` holds **linear** sRGB components in `0...1`, not gamma-encoded ones.
- `PaletteColor(srgb:_:_:)` converts an 8-bit gamma-encoded triple to linear on construction.
- Eight categorical colours, in a light and a dark variant. Beyond eight, `colour(forSeries:dark:)`
  cycles — deliberately, as a signal: a chart that reaches it should be labelling series directly.
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
  backgrounds, following the same principle. That is a weaker claim than adopting a published set,
  and it is the accurate one.
- **The CVD verification is specified and not implemented.** The intended check — simulate
  deuteranomaly by Machado's model, then require ΔE2000 of at least 15 between every pair — is not in
  the code, and neither Machado's model nor CIEDE2000 is implemented here. Both are cited above
  because they are the basis of a planned test, not of shipping behaviour.

## What it costs and where it lies

- **"CVD-safe" is currently inherited, not measured.** Until the ΔE2000-after-Machado check exists,
  the property this palette claims rests on the principle it was chosen by, and any reader is
  entitled to treat it as a hypothesis. It is marked as one here for that reason.
- The dark variant is a hand-lifted version of the light one, not a re-derivation. Its contrast
  against a dark ground has not been measured either.
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

Mutation-checked: replacing the palette with a single colour, dropping the transfer function,
substituting a plain 2.2 gamma for the piecewise curve, using `abs()` instead of a floored modulo,
and collapsing the three channels onto one each fail at least two tests.

**The central claim still has no test.** Separability under colour vision deficiency needs
Machado's simulation and CIEDE2000, neither of which is implemented — so "CVD-safe" remains
inherited from the sources above rather than measured here, and the tests below it prove the
mechanics, not the perception.
