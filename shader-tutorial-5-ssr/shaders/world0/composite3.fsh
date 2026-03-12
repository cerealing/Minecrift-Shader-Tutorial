#version 460 compatibility

#include "/lib/settings.glsl"

const bool colortex4Clear = false;
const bool colortex5Clear = false;
const bool colortex11Clear = false;
const bool colortex12Clear = false;

in vec2 texcoord;

uniform float frameTimeCounter;
uniform float worldTime;

uniform vec3 shadowLightPosition;
uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;
uniform mat4 gbufferPreviousModelView;
uniform mat4 gbufferPreviousProjection;
uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;

uniform vec2 texelSize;
uniform sampler2D depthtex0;
uniform sampler2D depthtex2;
uniform sampler2D colortex0;
uniform sampler2D colortex4;
uniform sampler2D colortex7;
uniform sampler2D colortex11;
uniform sampler2D colortex12;

vec3 ndcToViewPos(vec3 ndc)
{
    vec4 v = gbufferProjectionInverse * vec4(ndc, 1.0);
    return v.xyz / max(v.w, 1e-6);
}

vec3 SrgbToLinear(vec3 c)
{
    return pow(max(c, vec3(0.0)), vec3(2.2));
}

vec3 LinearToSrgb(vec3 c)
{
    return pow(max(c, vec3(0.0)), vec3(1.0 / 2.2));
}

float waterWaveHeight(vec2 xz)
{
    float t = frameTimeCounter * (0.7 + WAVE_SPEED * 1.3);
    float wave = 0.0;
    wave += sin(xz.x * 0.11 + t * 1.7);
    wave += cos(xz.y * 0.14 - t * 1.3);
    wave += sin((xz.x + xz.y) * 0.07 + t * 0.9);
    wave += cos((xz.x - xz.y) * 0.05 - t * 1.1);
    return wave * 0.05 * WAVE_STRENGTH;
}

vec3 waterNormalWorld(vec3 worldPos)
{
    float eps = 0.35;
    vec2 xz = worldPos.xz;
    float hx0 = waterWaveHeight(xz - vec2(eps, 0.0));
    float hx1 = waterWaveHeight(xz + vec2(eps, 0.0));
    float hz0 = waterWaveHeight(xz - vec2(0.0, eps));
    float hz1 = waterWaveHeight(xz + vec2(0.0, eps));
    return normalize(vec3(hx0 - hx1, eps * 2.0, hz0 - hz1));
}

vec2 viewToScreenUv(vec3 viewPos)
{
    vec4 clipPos = gbufferProjection * vec4(viewPos, 1.0);
    vec2 ndc = clipPos.xy / max(clipPos.w, 1e-6);
    return ndc * 0.5 + 0.5;
}

vec3 screenToView(vec2 uv, float depth)
{
    return ndcToViewPos(vec3(uv * 2.0 - 1.0, depth * 2.0 - 1.0));
}

float waterMask(vec2 uv)
{
    return step(0.02, texture(colortex7, uv).r);
}

vec3 sampleReflectionFallback(vec2 uv)
{
    vec2 safeUv = clamp(uv, texelSize * 2.0, vec2(1.0) - texelSize * 2.0);
    return texture(colortex0, safeUv).rgb;
}

vec3 traceWaterSSR(vec3 viewPos, vec3 reflectDir, out float hitMask)
{
    const int SSR_STEPS = 100;
    vec3 rayPos = viewPos + reflectDir * 0.45;
    float stride = 0.45;
    vec2 lastUv = gl_FragCoord.xy * texelSize;
    hitMask = 0.0;

    for (int i = 0; i < SSR_STEPS; i++)
    {
        rayPos += reflectDir * stride;
        //stride *= 1.08;

        vec2 uv = viewToScreenUv(rayPos);

        if (any(lessThan(uv, vec2(0.001))) || any(greaterThan(uv, vec2(0.999))))
        {
            break;
        }

        lastUv = uv;

        float sceneDepth = texture(depthtex0, uv).r;
        if (sceneDepth >= 0.999999)
        {
            continue;
        }

        vec3 scenePos = screenToView(uv, sceneDepth);
        float depthDelta = scenePos.z - rayPos.z;

        if (depthDelta > 0.0 && depthDelta < 0.9 + stride * 0.35 && waterMask(uv) < 0.5)
        {
            hitMask = 1.0 - float(i) / float(SSR_STEPS);
            return texture(colortex0, uv).rgb;
        }
    }

    hitMask = 0.0;
    return sampleReflectionFallback(lastUv);
}

/* RENDERTARGETS: 0,4,11,12 */
//layout(location = 0) out vec4 color;
//layout(location = 0) out vec4 color;

void main()
{
	

    vec2 tc = gl_FragCoord.xy * texelSize;

    vec3 ndc = vec3(tc * 2.0 - 1.0, 0.5);
    vec3 viewFar = ndcToViewPos(ndc);
    vec3 viewDirView = normalize(viewFar);
    vec3 viewDirWorld = normalize(mat3(gbufferModelViewInverse) * viewDirView);

    vec3 cameraWorld = cameraPosition;

    

    vec4 screenUV = vec4(tc, 1.0, 1.0);
    vec4 NDCPos = vec4(screenUV.xyz * 2.0 - 1.0, 1.0);
    vec4 projectPos = gbufferProjectionInverse * NDCPos;
    vec4 viewPos = projectPos / max(projectPos.w, 0.00001);
    vec4 worldPos = gbufferModelViewInverse * viewPos;
    worldPos.xyz += previousCameraPosition - cameraPosition;
    vec4 previousViewPos = gbufferPreviousModelView * worldPos;
    vec4 previousProjectionPos = gbufferPreviousProjection * previousViewPos;
    vec4 previousNDCPos = previousProjectionPos / max(previousProjectionPos.w, 0.00001);
    vec2 previousScreenUV = previousNDCPos.xy * 0.5 + 0.5;

    vec2 prevUv = previousScreenUV;
    //prevUv.y = -prevUv.y + 1.0;
    bool badUv = any(isnan(prevUv)) || any(isinf(prevUv));
    float inScreen = badUv ? 0.0 : (
        step(0.0001, prevUv.x) * step(prevUv.x, 0.9999) *
        step(0.0001, prevUv.y) * step(prevUv.y, 0.9999)
    );

    vec2 prevUvClamped = clamp(prevUv, vec2(0.0), vec2(1.0));

    float depth = texture2D(depthtex0, tc).r;
	vec4 albedo1 = texture2D(colortex0, tc);
	vec4 albedo2 = texture2D(colortex4, tc);
    vec4 albedo3 = texture2D(colortex12, prevUvClamped);
    float isWater = waterMask(tc);

    float if_sky = float(depth > 0.9999999);

    vec4 mixColorCloud = mix(albedo2, albedo3, 0.9 * inScreen);
    vec4 mixColorSky = mixColorCloud;
    mixColorSky.xyz = LinearToSrgb(mixColorSky.rgb);
    //mixColorSky.b += (1.0 - mixColorCloud.a) * 1.2;
    //mixColor1.rgb = LinearToSrgb(mixColor1.rgb);
    vec4 mixColorTerrain = mix(albedo1, mixColorSky, if_sky);
    
    //mixColor2.rgb += vec3(0.0, 0.0, 1.0);
    //vec4 mixColor = mix(albedo2, albedo3, 0.0);
    
    //mixColor.rgb = LinearToSrgb(mixColor.rgb);

    //mixColor = mix(albedo1, mixColor, if_sky);

    if (isWater > 0.5 && depth < 0.999999)
    {
        vec3 viewPosWater = screenToView(tc, depth);
        vec3 worldPosWater = (gbufferModelViewInverse * vec4(viewPosWater, 1.0)).xyz;
        mat3 viewToWorld = mat3(gbufferModelViewInverse);
        mat3 worldToView = transpose(viewToWorld);
        vec3 normalWorld = waterNormalWorld(worldPosWater);
        vec3 normalView = normalize(worldToView * normalWorld);
        vec3 reflectDir = normalize(reflect(normalize(viewPosWater), normalView));

        if (reflectDir.z < -0.05)
        {
            float hitMask = 0.0;
            vec3 reflection = traceWaterSSR(viewPosWater + normalView * 0.15, reflectDir, hitMask);

            float NoV = clamp(dot(normalView, normalize(-viewPosWater)), 0.0, 1.0);
            float fresnel = 0.02 + 0.98 * pow(1.0 - NoV, 5.0);
            float edgeFade = clamp(1.0 - distance(tc, clamp(tc, vec2(0.08), vec2(0.92))) * 6.0, 0.0, 1.0);

            //float ssrAmount = clamp(mix(0.35, 1.0, hitMask) * fresnel * edgeFade * 1.35, 0.0, 1.0);
            //vec3 waterTint = vec3(0.78, 0.9, 0.96);
            //mixColorTerrain.rgb *= waterTint;
            //mixColorTerrain.rgb = mix(mixColorTerrain.rgb, reflection, ssrAmount);
            mixColorTerrain.rgb = mix(mixColorTerrain.rgb, reflection, hitMask);
        }
    }
    
    
    //gl_FragData[0] = albedo2;//mixColorTerrain;
    gl_FragData[0] = mixColorTerrain;
    gl_FragData[2] = mixColorCloud;


	//color = albedo;
}
