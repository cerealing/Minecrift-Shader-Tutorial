#version 460 compatibility

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
//uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
//uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;

uniform vec2 texelSize;
uniform sampler2D depthtex0;
uniform sampler2D depthtex2;
uniform sampler2D colortex0;
uniform sampler2D colortex4;
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
    
    
    //gl_FragData[0] = albedo2;//mixColorTerrain;
    gl_FragData[0] = mixColorTerrain;
    gl_FragData[2] = mixColorCloud;


	//color = albedo;
}
