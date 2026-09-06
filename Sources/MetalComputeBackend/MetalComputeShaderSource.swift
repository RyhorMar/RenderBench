import Foundation

/// The compute kernel and the line-drawing pipeline, as source compiled once when a renderer is
/// built.
///
/// SwiftPM cannot compile `.metal` files — see `Sources/MetalBackend/MetalShaderSource.swift`'s
/// doc comment for the full reasoning, verified on this toolchain before that file was written and
/// unchanged since. The same pattern applies here: `MTLDevice.makeLibrary(source:)` at renderer
/// construction, not per frame. Both the reduction kernel and the line pipeline live in one source
/// string so the compile — reported separately, never folded into a frame's time — happens once.
enum MetalComputeShaderSource {
    static let reduceFunction = "minmax_reduce_columns"
    static let vertexFunction = "compute_chart_line_vertex"
    static let fragmentFunction = "compute_chart_line_fragment"

    /// - Note: `x`/`y` inside the kernel are plain `float`, which is safe here specifically because
    ///   every coordinate this backend hands the GPU is already normalised to `0...1` by
    ///   `FramePreparation`'s projection. The project's `Double`-for-time rule exists because of
    ///   unix time's ULP at that magnitude (~128 s at the current epoch), a hazard that does not
    ///   exist in a unit range.
    static let source = """
    #include <metal_stdlib>
    using namespace metal;

    /// One bucket's reduction: up to two points, in the carrier order they occurred, and how many
    /// of the two are real. `count == 0` means the bucket's span of x held no point at all, which
    /// happens when a run's points are not evenly spread across its own x extent.
    struct BucketResult {
        float2 a;
        float2 b;
        uint count;
        uint _padding;
    };

    /// Per-bucket MinMax over one contiguous run, bucketed by normalised x after projection.
    ///
    /// One thread per output column (bucket). Points within a run arrive ordered by x — carrier
    /// order is preserved through projection, a project invariant — so each thread finds its
    /// bucket's index range with a binary search rather than a linear scan from the start: with
    /// several thousand points in a run and a few hundred buckets, a linear scan would redo the
    /// same prefix of the array from every thread, while the search touches O(log n) points before
    /// the O(bucket size) min/max pass that no strategy can avoid.
    ///
    /// Both the minimum and the maximum are the *first* occurrence of that value in the bucket —
    /// `<` and `>`, never `<=`/`>=` — so a flat run of equal samples is not silently reassigned to
    /// a later index than the CPU path would choose for the same tie.
    kernel void minmax_reduce_columns(
        const device float2 *points [[buffer(0)]],
        constant uint &pointCount [[buffer(1)]],
        constant float &runMinX [[buffer(2)]],
        constant float &bucketWidth [[buffer(3)]],
        constant uint &columns [[buffer(4)]],
        device BucketResult *results [[buffer(5)]],
        uint gid [[thread_position_in_grid]]
    ) {
        if (gid >= columns) return;

        float start = runMinX + bucketWidth * float(gid);
        // The last bucket's upper edge is +inf rather than `runMinX + bucketWidth * columns`, so
        // floating-point drift in that product can never leave the run's final point homeless in
        // a bucket range search that excludes it — mirroring the CPU path's `last.nextUp` for the
        // same reason, in a form that makes sense for a bound expressed as a strict less-than.
        float end = (gid == columns - 1) ? INFINITY : (runMinX + bucketWidth * float(gid + 1));

        uint lo = 0;
        uint hi = pointCount;
        while (lo < hi) {
            uint mid = (lo + hi) / 2;
            if (points[mid].x < start) { lo = mid + 1; } else { hi = mid; }
        }
        uint rangeStart = lo;

        lo = rangeStart;
        hi = pointCount;
        while (lo < hi) {
            uint mid = (lo + hi) / 2;
            if (points[mid].x < end) { lo = mid + 1; } else { hi = mid; }
        }
        uint rangeEnd = lo;

        if (rangeStart >= rangeEnd) {
            results[gid].count = 0;
            return;
        }

        uint minIndex = rangeStart;
        uint maxIndex = rangeStart;
        for (uint i = rangeStart; i < rangeEnd; i++) {
            if (points[i].y < points[minIndex].y) { minIndex = i; }
            if (points[i].y > points[maxIndex].y) { maxIndex = i; }
        }

        uint earlier = min(minIndex, maxIndex);
        uint later = max(minIndex, maxIndex);
        results[gid].a = points[earlier];
        if (earlier == later) {
            results[gid].count = 1;
        } else {
            results[gid].b = points[later];
            results[gid].count = 2;
        }
    }

    // Everything below draws the reduced points, exactly as `MetalBackend`'s own
    // `chart_line_vertex`/`chart_line_fragment` do — instanced quads expanding a polyline into
    // triangles, because Metal has no wide-line primitive. Duplicated rather than shared: this
    // package's backends never depend on one another, so the handful of lines a comparison stand
    // would save are kept here instead, under names of their own so the two libraries never
    // collide inside the same process.

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

    vertex VertexOut compute_chart_line_vertex(
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
        float2 direction = length2 > 1e-12f ? delta * rsqrt(length2) : float2(1.0f, 0.0f);
        float2 normal = float2(-direction.y, direction.x);

        float along = (vertexID == 2u || vertexID == 3u || vertexID == 5u) ? 1.0f : 0.0f;
        float side = (vertexID == 1u || vertexID == 4u || vertexID == 5u) ? 1.0f : -1.0f;

        float2 centre = mix(a, b, along);
        centre += direction * (along * 2.0f - 1.0f) * uniforms.extend;
        centre += normal * side * uniforms.halfWidth;

        float2 clip = float2(
            centre.x / uniforms.viewportPixels.x * 2.0f - 1.0f,
            1.0f - centre.y / uniforms.viewportPixels.y * 2.0f
        );

        VertexOut out;
        out.position = float4(clip, 0.0f, 1.0f);
        out.colour = uniforms.colour;
        return out;
    }

    fragment float4 compute_chart_line_fragment(VertexOut in [[stage_in]]) {
        return in.colour;
    }
    """
}
