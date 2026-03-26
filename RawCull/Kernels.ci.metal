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
