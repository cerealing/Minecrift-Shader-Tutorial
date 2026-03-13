#version 460 compatibility

#include "/lib/settings.glsl"

const bool colortex4Clear = false;
const bool colortex5Clear = false;

const vec3 SunOrMoonLight[2] = vec3[2](
    vec3(sunColorR, sunColorG, sunColorB),
    vec3(moonColorR, moonColorG, moonColorB)
);

const vec2 SunOrMoonIlluminanceAndTemp[2] = vec2[2](
    vec2(sun_illuminance, Sun_temp),
    vec2(moon_illuminance, Moon_temp)
);

in vec2 texcoord;
flat in float SunOrMoon;

uniform float frameTimeCounter;
uniform float worldTime;
uniform vec2 texelSize;
uniform vec3 shadowLightPosition;
uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;
uniform mat4 gbufferPreviousModelView;
uniform mat4 gbufferPreviousProjection;
//uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
//uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform sampler2D depthtex0;
uniform sampler2D depthtex3;
uniform sampler2D colortex0;
uniform sampler2D colortex4;
uniform sampler2D colortex5;

uniform float firstFrame;

/* RENDERTARGETS: 4 */

vec3 ndcToViewPos(vec3 ndc)
{
    vec4 v = gbufferProjectionInverse * vec4(ndc, 1.0);
    return v.xyz / max(v.w, 1e-6);
}

float hgPhase(float cosTheta, float g)
{
    float gg = g * g;
    float denom = pow(max(1.0 + gg - 2.0 * g * cosTheta, 1e-4), 1.5);
    return (1.0 - gg) / (4.0 * 3.14159265 * denom);
}

float cloudHash13(vec3 p)
{
    return fract(sin(dot(p, vec3(127.1, 311.7, 213.9))) * 43758.5453123);
}

float cloudNoise3(vec3 p)
{
    vec3 i = floor(p);
    vec3 fa = fract(p);
    vec3 u = fa * fa * (vec3(3.0) - 2.0 * fa);

    float a = cloudHash13(i + vec3(0.0, 0.0, 0.0));
    float b = cloudHash13(i + vec3(1.0, 0.0, 0.0));
    float c = cloudHash13(i + vec3(0.0, 1.0, 0.0));
    float d = cloudHash13(i + vec3(1.0, 1.0, 0.0));

    float e = cloudHash13(i + vec3(0.0, 0.0, 1.0));
    float f = cloudHash13(i + vec3(1.0, 0.0, 1.0));
    float g = cloudHash13(i + vec3(0.0, 1.0, 1.0));
    float h = cloudHash13(i + vec3(1.0, 1.0, 1.0));

    float mx00 = mix(a, b, u.x);
    float mx10 = mix(c, d, u.x);
    float mx01 = mix(e, f, u.x);
    float mx11 = mix(g, h, u.x);

    float mxy0 = mix(mx00, mx10, u.y);
    float mxy1 = mix(mx01, mx11, u.y);

    float mxyz = mix(mxy0, mxy1, u.z);

    return mxyz;
}

float cloudFbm3(vec3 p)
{
    p *= 0.00187;
    float value = 0.0;
    float amp = 0.5;
    for (int i = 0; i < 5; i++)
    {
        value += amp * cloudNoise3(p);
        p *= 2.0;
        amp *= 0.5;
    }
    return value;
}

float cloudDensityAt(vec3 worldPos, float cloudBottomY, float cloudTopY)
{
    float h = (worldPos.y - cloudBottomY) / max(cloudTopY - cloudBottomY, 1e-3);
    h = clamp(h, 0.0, 1.0);

    float bottomFade = smoothstep(0.0, 0.16, h);
    float topFade = 1.0 - smoothstep(0.75, 1.0, h);
    float heightShape = bottomFade * topFade;

    vec3 wind = vec3(frameTimeCounter * 0.015, frameTimeCounter * 0.010, 0.0);

    float low = cloudFbm3((worldPos * 8.5 + wind) * 0.7);
    //float high = cloudFbm3(worldPos * 2.5+ wind * 2.0);

    float coverage = 0.35;
    //float n = (low * 1.78 + high * 0.22) * high * 1.0;
    float n = low * low * 1.2;
    float d = smoothstep(coverage, coverage + 0.15, n);

    d = pow(clamp(d, 0.0, 1.0), 0.25);

    d *= heightShape * 1.5;
    return clamp(d, 0.0, 1.0);
}

float cloudLightTransmittance(vec3 worldPos, vec3 sunDir, float cloudBottomY, float cloudTopY)
{
    const int LIGHT_STEPS = 6;
    float stepLen = 18.0;
    float od = 0.0;

    vec3 p = worldPos;
    for (int i = 0; i < LIGHT_STEPS; i++)
    {
        p += sunDir * stepLen;
        if (p.y < cloudBottomY || p.y > cloudTopY)
            break;
        float d = cloudDensityAt(p, cloudBottomY, cloudTopY);
        od += d * stepLen;
    }

    float sigmaExt = 0.055;
    return exp(-od * sigmaExt * 0.45);
}

void main()
{
    vec2 uv = texcoord;

    float depth = texture(depthtex0, uv).r;
    vec3 sceneColor = texture(colortex5, uv).rgb;

    #ifndef OPEN_VOLUNMETRIC_CLOUDSCAPES
        gl_FragData[0] = vec4(sceneColor, 0.0);
        return;
    #endif

    vec3 ndc = vec3(uv * 2.0 - 1.0, 0.5);
    vec3 viewFar = ndcToViewPos(ndc);
    vec3 viewDirView = normalize(viewFar);
    vec3 viewDirWorld = normalize(mat3(gbufferModelViewInverse) * viewDirView);

    vec3 cameraWorld = cameraPosition;

    vec3 sunDirWorld = normalize(mat3(gbufferModelViewInverse) * normalize(shadowLightPosition));

    float denom = viewDirWorld.y;
    if (abs(denom) < 1e-5)
    {
        gl_FragData[0] = vec4(sceneColor, 0.0);
        return;
    }

    if (cameraWorld.y < -100)
    {
        gl_FragData[0] = vec4(1.0, 0.0, 0.0, 1.0);
    }

    float t0 = (cloudBottom - cameraWorld.y) / denom;
    float t1 = (cloudTop - cameraWorld.y) / denom;
    float tEntry = min(t0, t1);
    float tExit = max(t0, t1);

    if (tExit <= 0.0)
    {
        gl_FragData[0] = vec4(sceneColor, 0.0);
        return;
    }

    tEntry = max(tEntry, 0.0);

    // Raymarch through the cloud slab
    const int MAX_STEPS = 96;
    float segmentLen = max(tExit - tEntry, 0.0);
    float stepLen = 12.0;
    int steps = int(clamp(ceil(segmentLen / stepLen), 1.0, float(MAX_STEPS)));

    float jitter = cloudHash13(viewDirWorld * vec3(173.3, 271.9, 234.9) + frameTimeCounter) - 0.5;
    float t = tEntry + jitter * stepLen;

    float transmittance = 1.0;
    float deep = 0.0;
    vec3 accum = vec3(0.0);

    float g = 0.45;
    float phase = hgPhase(dot(viewDirWorld, sunDirWorld), g);

    vec3 lightColor = mix(vec3(moonColorR, moonColorG, moonColorB), vec3(sunColorR, sunColorG, sunColorB), SunOrMoon);
    float lightIntensity = mix(moon_illuminance, sun_illuminance, SunOrMoon);
    vec3 sunRadiance = lightColor * (lightIntensity * 1.0);

    float darkInt = 0.055;
    float lightInt = 0.09;
    vec3 cloudAlbedo = vec3(1.0);
    vec3 ambientRadiance = mix(sceneColor, vec3(1.0), 0.45);
    float ambientStrength = 0.75;

    for (int i = 0; i < MAX_STEPS; i++)
    {
        if (i >= steps)
            break;

        float ti = t + (float(i) + 0.5) * stepLen;
        if (ti > tExit)
            break;

        vec3 p = cameraWorld + viewDirWorld * ti;

        float d = cloudDensityAt(p, cloudBottom, cloudTop);
        if (d > 1e-4)
        {
            deep += d;
            float extinction = deep * darkInt;
            float stepTrans = exp(-extinction * stepLen * 0.15);

            float lightT = cloudLightTransmittance(p, sunDirWorld, cloudBottom, cloudTop);
            vec3 inscatter = (sunRadiance * lightT * phase + ambientRadiance * ambientStrength) * (lightInt * d) * cloudAlbedo;

            accum += transmittance * inscatter * 2.0;

            transmittance *= (1.0 - d) * 0.6;//stepTrans;
            if (transmittance < 0.01)
                break;
        }
    }

    vec3 outColor = sceneColor * transmittance * 0.7 + accum * phase * 3.0;
    float opacity = clamp(1.0 - transmittance, 0.0, 1.0);

    // Final artistic push toward cotton-white
    outColor = pow(outColor, vec3(0.5));

    vec4 outPx = vec4(outColor, opacity);
    gl_FragData[0] = outPx;
}
