#include <metal_stdlib>
using namespace metal;

// Compiled by Xcode into the demo app's own bundle. SwiftPM 6.2 does not compile `.metal` files at
// all, and `colorEffect`/`ShaderLibrary.default` has no source-string equivalent to
// `MTLDevice.makeLibrary(source:)` the way `MetalShaderSource` uses for the Metal backend — a
// `[[stitchable]]` SwiftUI shader must be a real `.metal` file built into an app bundle. That is
// the whole reason this file lives under `Demo/` rather than in `Sources/ShaderBackend`, and why
// this method's equivalence test runs from `Demo/Tests` instead of from the package.
//
// `points`/`byteCount` describe one contiguous run, not a whole series: `ShaderLineBuffers` (in
// `Sources/ShaderBackend`) packs each run a break divides a series into as its own buffer and
// issues one invocation of this function per run, because a `[[stitchable]]` shader takes a fixed
// argument list and cannot itself notice a marker for "series ends here, next one starts" inside a
// single flat buffer without scanning for it on every pixel of every segment.
[[ stitchable ]] half4 chart_line(
    float2 position,
    half4 colour,
    device const float2 *points,
    int byteCount,
    float halfWidth,
    half4 lineColour
) {
    int count = byteCount / 8; // ShaderLineBuffers.pointStride: two packed Float32 per point.
    half coverage = 0.0h;
    for (int i = 0; i < count - 1; i++) {
        float2 a = points[i];
        float2 b = points[i + 1];
        float2 segment = b - a;
        float lengthSquared = max(dot(segment, segment), 1e-6);
        float t = clamp(dot(position - a, segment) / lengthSquared, 0.0, 1.0);
        float distance = length(position - (a + segment * t));
        // A one-point-wide antialiased band around `halfWidth`: coverage is 1 well inside the
        // stroke, 0 well outside it, and eases between the two across the edge a hard threshold
        // would alias. `max` across segments lets two segments meeting at a shared vertex both
        // contribute without doubling coverage in the corner they overlap.
        half edge = half(1.0 - smoothstep(halfWidth - 0.5, halfWidth + 0.5, distance));
        coverage = max(coverage, edge);
    }
    return half4(lineColour.rgb * coverage, coverage);
}
