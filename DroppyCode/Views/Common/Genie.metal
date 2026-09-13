#include <metal_stdlib>
using namespace metal;

/// A genie effect in the style of macOS minimizing a window to the Dock.
///
/// The funnel is fixed in space: its sides bend from the row's width at the row down to a narrow
/// neck at the target. The row first pinches into that funnel, then slides down through it, and
/// whatever passes the neck is gone. SwiftUI hands each destination pixel in and gets the source
/// pixel to sample back, so a pixel outside the funnel or past the row samples nothing.
///
/// `progress` is animation progress from 0 to 1, never a clock. `source` is the row's frame
/// (x, y, width, height) and `target` the neck, both in the layer's coordinates.
[[ stitchable ]] float2 genie(float2 position, float progress, float4 source, float2 target) {
    const float2 nothing = float2(-100000.0, -100000.0);
    float t = clamp(progress, 0.0, 1.0);
    float pinch = smoothstep(0.0, 0.45, t);
    float slide = smoothstep(0.2, 1.0, t);

    float x0 = source.x;
    float y0 = source.y;
    float width = source.z;
    float height = source.w;
    float travel = max(target.y - y0, height);

    if (position.y > target.y) {
        return nothing;
    }

    // How far down the funnel this row of pixels sits, 0 at the row's top and 1 at the neck.
    float depth = clamp((position.y - y0) / travel, 0.0, 1.0);
    float bend = pinch * smoothstep(0.0, 1.0, depth);
    float neck = min(24.0, width);
    float left = mix(x0, target.x - neck * 0.5, bend);
    float right = mix(x0 + width, target.x + neck * 0.5, bend);
    float u = (position.x - left) / max(right - left, 0.0001);
    if (u < 0.0 || u > 1.0) {
        return nothing;
    }

    // The row slides down into the funnel as the animation runs.
    float sourceY = position.y - slide * (target.y - y0);
    if (sourceY < y0 || sourceY > y0 + height) {
        return nothing;
    }
    return float2(x0 + u * width, sourceY);
}
