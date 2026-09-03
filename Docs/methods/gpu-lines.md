# GPU line expansion

## What it does

Turns a polyline into triangles on the GPU. The CPU uploads the points once per frame and issues
one draw call per series; the vertex shader reads two consecutive points per instance and emits the
six vertices of a quad that covers the segment at the requested stroke width.

## Where it lives

`Sources/MetalBackend/`. `MetalChartGeometry` builds the buffers and touches no Metal type, so it
is testable on a host with no GPU; `MetalLineRenderer` owns the device objects and the encoding;
`MetalRenderTarget` renders off screen for the equivalence comparison; `MetalChartView` puts an
`MTKView` on screen without letting it run its own clock.

## Contract

- Input is a `PreparedFrame` — the same windowed, reduced, projected frame every other backend
  draws, so nothing about the data path differs between backends.
- Positions are in device pixels with the origin at the top left. The shader offsets along a
  segment normal by half the stroke width, and that is a constant width only in the space the
  rasteriser measures.
- A break in the data is a segment that is not indexed. No drawn segment spans one.
- Colours arrive linear and the render target is `bgra8Unorm_srgb`, so the hardware applies the
  transfer function on write.
- The renderer holds a ring of buffers and a semaphore. Writing into a shared-storage buffer the
  GPU is still reading is a data race, not a rare glitch.

## Why this method

Metal has no wide-line primitive. `MTLPrimitiveType.line` rasterises one device pixel with no
width and no antialiasing, which would draw a visibly thinner chart than the other backends and
win the comparison on a difference in output rather than in method. Expanding on the CPU is the
other option and is what most chart libraries do; doing it in the vertex shader is what makes this
backend a different method rather than the same method with a different upload.

## Provenance

The instanced-quad expansion of a polyline is standard practice rather than a published algorithm;
the clearest written treatment is Rye Terrell's *Instanced Line Rendering* (2019), and the
technique appears in essentially this form in `regl`, `deck.gl` and `three.js`'s `Line2`. The
antialiasing here is 4× multisampling done by the hardware, not the analytic coverage those
libraries compute in a fragment shader.

## How this implementation differs from the source

Joins are filled by extending each segment by half a stroke width at both ends rather than by
emitting join geometry. It is cheaper and it is not the same shape: at the two ends of a polyline
it produces a square cap where Core Graphics produces a round one, and on a sharp turn it fills
more than a bevel would. Measured on the reference chart, the difference this makes is below the
measurement floor — the same comparison with the extension switched off scores 32.35 dB against
32.47 dB with it — so the join treatment is not what separates this backend from the Core Graphics
ones.

## What it costs and where it lies

The shader is compiled from source when a renderer is built: **48 ms on an M3 Pro**, once, before
the first frame exists. It is not a per-frame cost and it is reported separately
(`MetalLineRenderer.libraryCompileNanoseconds`) so that it cannot be quietly folded into one.
SwiftPM 6.2 does not compile `.metal` files at all — it reports them as unhandled resources and
produces no `default.metallib` — so the alternatives were a build plugin invoking `xcrun metal` on
every host build or moving the shader into the demo's Xcode project, which would leave the backend
untestable on its own.

Where it lies, or could: the simulator's GPU is named `Apple iOS simulator GPU` and belongs to
family `apple1`. It runs, and its timings describe the host's translation layer rather than any
phone. No number from it belongs in a results file.

This is the only backend so far whose rasterisation is measured rather than inferred: a command
buffer carries its own start and end timestamps, so the `gpu` column is filled from the GPU's clock
instead of by subtracting one host measurement from another.

## Verified by

- `Tests/MetalBackendTests/MetalGeometryTests.swift` — segment counts, breaks, pixel-space
  projection, and that the uniform struct is the size the shader declares.
- `Tests/MetalBackendTests/MetalRenderTargetTests.swift` — the shader compiles and declares both
  functions (the build cannot check this, so a test does); the background is exactly the chrome
  colour; two renders are bit-identical; a two-point stroke on a whole coordinate is byte-identical
  to the Core Graphics reference; the full chart passes the structural comparison; and four
  deliberately wrong renders are rejected by it.
