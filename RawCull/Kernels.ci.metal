//
//  Kernels.ci.metal
//  RawCull
//
//  Created by Thomas Evensen on 24/02/2026.
//

#include <CoreImage/CoreImage.h>

extern "C" {
    float4 sobelMagnitude(coreimage::sample_t s) {
        float gx = s.r;
        float gy = s.g;
        float mag = coreimage::sqrt(gx * gx + gy * gy);
        return float4(mag, mag, mag, 1.0);
    }
}
