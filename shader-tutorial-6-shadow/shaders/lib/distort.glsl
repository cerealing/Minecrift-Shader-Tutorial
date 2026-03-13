// Included file (do not put #version here)

// Absolute include paths start from the shader pack "shaders" directory.
#include "/lib/settings.glsl"

#define SHADOW_RADIUS 8
#define SHADOW_RANGE 4
#define SIGMA 16.0

const int shadowMapResolution = 8192;//16384;

vec3 distortShadowClipPos(vec3 shadowClipPos)
{
    float distortionFactor = length(shadowClipPos.xy);
    distortionFactor += 0.1;

    shadowClipPos.xy /= distortionFactor;
    shadowClipPos.z *= 0.2;
    return shadowClipPos;
}