//
//  Kernels.ci.metal
//  RawCull
//
//  Created by Thomas Evensen on 24/02/2026.
//
#include <metal_stdlib>
using namespace metal;
#include <CoreImage/CoreImage.h>

extern "C" {
    namespace coreimage {
        // Per-pixel edge energy via a 3×3 discrete Laplacian.
        //
        // Stencil: laplace = 8·center − Σ(8 neighbours).  A high |laplace|
        // indicates a strong second-derivative edge; a flat patch gives ~0.
        //
        // The channel-wise |laplace| is collapsed into a single scalar using
        // the Rec. 601 luminance weighting (0.299, 0.587, 0.114) — the same
        // weighting used by the histogram pass so "edge energy" stays
        // perceptually consistent with "brightness".
        //
        // The scalar is packed into r/g/b with a=1 so downstream CIFilters
        // (CIColorMatrix gain → CIColorThreshold → CIMorphology*) can read
        // it from any channel without a format conversion.
        float4 focusLaplacian(sampler src) {
            float2 pos = src.coord();

            float4 c  = src.sample(pos);
            float4 n  = src.sample(pos + float2( 0, -1));
            float4 s  = src.sample(pos + float2( 0,  1));
            float4 e  = src.sample(pos + float2( 1,  0));
            float4 w  = src.sample(pos + float2(-1,  0));
            float4 ne = src.sample(pos + float2( 1, -1));
            float4 nw = src.sample(pos + float2(-1, -1));
            float4 se = src.sample(pos + float2( 1,  1));
            float4 sw = src.sample(pos + float2(-1,  1));

            float4 laplace = 8.0 * c - (n + s + e + w + ne + nw + se + sw);
            float energy   = dot(abs(laplace.rgb), float3(0.299, 0.587, 0.114));

            return float4(energy, energy, energy, 1.0);
        }
    }
}
