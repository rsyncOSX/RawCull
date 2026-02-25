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
            
            // Sample neighbors
            float4 center = src.sample(pos);
            float4 left   = src.sample(pos + float2(-1.0, 0.0));
            float4 right  = src.sample(pos + float2(1.0, 0.0));
            float4 top    = src.sample(pos + float2(0.0, -1.0));
            float4 bottom = src.sample(pos + float2(0.0, 1.0));
            
            // Second-order derivative (Laplacian)
            // This ignores linear gradients (blurred feet) and finds spikes (sharp eyes)
            float4 laplace = 4.0 * center - (left + right + top + bottom);
            
            // Grayscale energy
            float energy = dot(abs(laplace.rgb), float3(0.299, 0.587, 0.114));
            
            // Boost the sharpest details
            float result = pow(energy, 1.5) * 20.0;
            
            return float4(result, 0.0, 0.0, 1.0);
        }
    }
}
