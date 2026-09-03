import Foundation

/// The shader program, as source compiled when a renderer is built.
///
/// A `.metal` file in the target would be the obvious spelling and does not work: SwiftPM 6.2
/// treats such a file as an unhandled resource — "found 1 file(s) which are unhandled" — produces
/// no `default.metallib`, and does not even generate the `Bundle.module` accessor that the usual
/// advice tells you to load the library from. Verified on this toolchain before this file was
/// written. The alternatives were a build-tool plugin shelling out to `xcrun metal`, which puts the
/// Metal toolchain on the critical path of every host build including the Linux-testable layers,
/// and moving the shader into the demo's Xcode project, which would leave the backend untestable
/// on its own. Source compiled at startup costs ~48 ms once on an M3 Pro and nothing per frame.
///
/// The compile is not free and is not hidden: ``MetalLineRenderer/libraryCompileNanoseconds``
/// reports it, and it is excluded from every frame measurement by construction — it happens before
/// the first frame exists.
enum MetalShaderSource {
    /// Names must match the strings the pipeline looks up; a typo is a runtime failure, and
    /// ``MetalLineRenderer`` turns it into a thrown error rather than a crash.
    static let vertexFunction = "chart_line_vertex"
    static let fragmentFunction = "chart_line_fragment"

    /// Instanced expansion of a polyline into screen-space quads.
    ///
    /// The GPU has no wide-line primitive: `MTLPrimitiveType.line` rasterises one device pixel
    /// with no antialiasing and no width, which would draw a visibly thinner chart than every
    /// other backend and win the comparison on a difference in output rather than in method. The
    /// polyline is therefore expanded into triangles. Doing that expansion here rather than on the
    /// CPU is the whole point of the backend: the CPU uploads points, the GPU builds geometry.
    ///
    /// Colours arrive linear and the render target is `_srgb`, so the hardware applies the
    /// transfer function on write. Encoding here as well would apply it twice.
    static let source = """
    #include <metal_stdlib>
    using namespace metal;

    struct ChartUniforms {
        float2 viewportPixels;
        float halfWidth;
        float extend;
        float4 colour;
    };

    struct VertexOut {
        float4 position [[position]];
        float4 colour;
    };

    vertex VertexOut chart_line_vertex(
        uint vertexID [[vertex_id]],
        uint instanceID [[instance_id]],
        const device float2 *points [[buffer(0)]],
        const device uint *segmentStarts [[buffer(1)]],
        constant ChartUniforms &uniforms [[buffer(2)]]
    ) {
        uint start = segmentStarts[instanceID];
        float2 a = points[start];
        float2 b = points[start + 1];

        float2 delta = b - a;
        float length2 = dot(delta, delta);
        // A segment of zero length has no direction; picking one keeps the quad degenerate
        // instead of producing NaN positions that the rasteriser would discard unpredictably.
        float2 direction = length2 > 1e-12f ? delta * rsqrt(length2) : float2(1.0f, 0.0f);
        float2 normal = float2(-direction.y, direction.x);

        // vertexID 0..5 walks two triangles of one quad: (along, side) pairs
        // (0,0) (0,1) (1,0) | (1,0) (0,1) (1,1).
        float along = (vertexID == 2u || vertexID == 3u || vertexID == 5u) ? 1.0f : 0.0f;
        float side = (vertexID == 1u || vertexID == 4u || vertexID == 5u) ? 1.0f : -1.0f;

        float2 centre = mix(a, b, along);
        centre += direction * (along * 2.0f - 1.0f) * uniforms.extend;
        centre += normal * side * uniforms.halfWidth;

        // Pixel space has its origin at the top left, clip space at the centre with y up.
        float2 clip = float2(
            centre.x / uniforms.viewportPixels.x * 2.0f - 1.0f,
            1.0f - centre.y / uniforms.viewportPixels.y * 2.0f
        );

        VertexOut out;
        out.position = float4(clip, 0.0f, 1.0f);
        out.colour = uniforms.colour;
        return out;
    }

    fragment float4 chart_line_fragment(VertexOut in [[stage_in]]) {
        return in.colour;
    }
    """
}
