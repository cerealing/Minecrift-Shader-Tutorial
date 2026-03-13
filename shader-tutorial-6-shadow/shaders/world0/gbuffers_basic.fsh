#version 460 compatibility

#include "/lib/distort.glsl"
#include "/lib/blocks.glsl"
#include "/lib/settings.glsl"

flat in float material_id;

flat in vec3 sunVec;
in vec4 color;
in vec4 lmtexcoord;
//flat in vec4 sunlightColor;
flat in float SunOrMoon;
in mat3 TBN;

uniform float wetness;
uniform vec3 sunPosition;
uniform vec3 shadowLightPosition;
uniform mat4 gbufferModelView; //this mat has problem
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform mat4 shadowModelView;
uniform mat4 shadowProjection;
uniform float viewWidth;
uniform float viewHeight;
uniform sampler2D gtexture;
uniform sampler2D lightmap;
uniform sampler2D normals;
uniform sampler2D specular;
uniform sampler2D shadowtex0;
uniform sampler2D shadowtex1;
uniform sampler2D shadowcolor0;
uniform sampler2D noisetex;

const int METAL_ID_BASE = 230;
const int METAL_COUNT = 8;
const vec3 METAL_N[METAL_COUNT] = vec3[METAL_COUNT](
    vec3(2.9114, 2.9497, 2.5845),   // 230 Iron
    vec3(0.18299, 0.42108, 1.3734), // 231 Gold
    vec3(1.3456, 0.96521, 0.61722), // 232 Aluminum
    vec3(3.1071, 3.1812, 2.3230),   // 233 Chrome
    vec3(0.27105, 0.67693, 1.3164), // 234 Copper
    vec3(1.9100, 1.8300, 1.4400),   // 235 Lead
    vec3(2.3757, 2.0847, 1.8453),   // 236 Platinum
    vec3(0.15943, 0.14512, 0.13547) // 237 Silver
);
const vec3 METAL_K[METAL_COUNT] = vec3[METAL_COUNT](
    vec3(3.0893, 2.9318, 2.7670), // 230 Iron
    vec3(3.4242, 2.3459, 1.7704), // 231 Gold
    vec3(7.4746, 6.3995, 5.3031), // 232 Aluminum
    vec3(3.3314, 3.3291, 3.1350), // 233 Chrome
    vec3(3.6092, 2.6248, 2.2921), // 234 Copper
    vec3(3.5100, 3.4000, 3.1800), // 235 Lead
    vec3(4.2655, 3.7153, 3.1365), // 236 Platinum
    vec3(3.9291, 3.1900, 2.3808)  // 237 Silver
);

const vec2 DIR_AMB[2] = vec2[2](
    vec2(0.55, 1.3),
    vec2(0.7, 0.5)
);

const vec3 SunOrMoonLight[2] = vec3[2](
    vec3(sunColorR, sunColorG, sunColorB),
    vec3(moonColorR, moonColorG, moonColorB)
);

const vec2 SunOrMoonIlluminanceAndTemp[2] = vec2[2](
    vec2(sun_illuminance, Sun_temp),
    vec2(moon_illuminance, Moon_temp)
);

#define diagonal3(m) vec3((m)[0].x, (m)[1].y, (m)[2].z )
#define projMAD(m, v) (diagonal3(m) * (v) + (m)[3].xyz)
#define project(prjectionMatrix, position) vec4(projMAD(prjectionMatrix, position), -position.z)
vec4 toClipSpace3(vec3 viewSpacePosition)
{
    return vec4(projMAD(gbufferProjection, viewSpacePosition), -viewSpacePosition.z);
}
vec3 projectAndDivide(mat4 prjectionMatrix, vec3 position)
{
    vec4 projectPos = project(prjectionMatrix, position);
    return projectPos.xyz / projectPos.w;
}

// Conductor (metal) Fresnel using complex IOR n + i k.
// GLSL has no 'complex' type; compute directly with real vec3 math.
vec3 conductorF0(vec3 n, vec3 k)
{
    vec3 nMinus1 = n - vec3(1.0);
    vec3 nPlus1 = n + vec3(1.0);
    vec3 numerator = nMinus1 * nMinus1 + k * k;
    vec3 denominator = nPlus1 * nPlus1 + k * k;
    return numerator / denominator;
}

// --- Complex Fresnel (no Schlick) ---
// Represent a complex number a + i b as vec2(a, b).
vec2 c_add(vec2 a, vec2 b) { return a + b; }
vec2 c_sub(vec2 a, vec2 b) { return a - b; }
vec2 c_conj(vec2 a) { return vec2(a.x, -a.y); }
float c_abs2(vec2 a) { return dot(a, a); }

vec2 c_mul(vec2 a, vec2 b)
{
    return vec2(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x);
}

vec2 c_div(vec2 a, vec2 b)
{
    // a / b = a * conj(b) / |b|^2
    float denom = c_abs2(b);
    return c_mul(a, c_conj(b)) / max(denom, 1e-20);
}

vec2 c_sqrt(vec2 z)
{
    // Principal complex square root.
    // sqrt(a + ib) = sqrt((|z|+a)/2) + sign(b) i sqrt((|z|-a)/2)
    float a = z.x;
    float b = z.y;
    float r = length(z);
    float t = sqrt(max(0.5 * (r + a), 0.0));
    float u = sqrt(max(0.5 * (r - a), 0.0));
    float s = (b < 0.0) ? -1.0 : 1.0;
    return vec2(t, s * u);
}

float fresnelConductorComplex1(float cosThetaI, float n, float k)
{
    // Exact Fresnel for conductors using complex eta = n + i k.
    cosThetaI = clamp(cosThetaI, 0.0, 1.0);
    float sin2ThetaI = max(0.0, 1.0 - cosThetaI * cosThetaI);

    vec2 eta = vec2(n, k);
    vec2 invEta = c_div(vec2(1.0, 0.0), eta);
    vec2 invEta2 = c_mul(invEta, invEta);

    // cosThetaT = sqrt(1 - (sinThetaI/eta)^2)
    vec2 cosThetaT = c_sqrt(c_sub(vec2(1.0, 0.0), c_mul(vec2(sin2ThetaI, 0.0), invEta2)));

    // r_parl = (eta*cosI - cosT) / (eta*cosI + cosT)
    vec2 etaCosI = c_mul(eta, vec2(cosThetaI, 0.0));
    vec2 r_parl = c_div(c_sub(etaCosI, cosThetaT), c_add(etaCosI, cosThetaT));

    // r_perp = (cosI - eta*cosT) / (cosI + eta*cosT)
    vec2 etaCosT = c_mul(eta, cosThetaT);
    vec2 r_perp = c_div(c_sub(vec2(cosThetaI, 0.0), etaCosT), c_add(vec2(cosThetaI, 0.0), etaCosT));

    // Unpolarized reflectance: (|r_parl|^2 + |r_perp|^2) / 2
    return 0.5 * (c_abs2(r_parl) + c_abs2(r_perp));
}

vec3 fresnelConductorComplex(float cosThetaI, vec3 n, vec3 k)
{
    return vec3(
        fresnelConductorComplex1(cosThetaI, n.r, k.r),
        fresnelConductorComplex1(cosThetaI, n.g, k.g),
        fresnelConductorComplex1(cosThetaI, n.b, k.b)
    );
}

// LabPBR extras (specular texture channels)
// B: 0..64 porosity, 65..255 subsurface scattering (both linear)
// A: 0..254 emissive (linear)
void decodeLabPBRExtras(vec4 spec, out float porosity, out float subsurface, out float emissive)
{
    float b = clamp(spec.b, 0.0, 1.0) * 255.0;
    float isSSS = step(64.5, b); // b >= 65 -> 1, else 0
    float p = clamp(b / 64.0, 0.0, 1.0);
    float s = clamp((b - 65.0) / (255.0 - 65.0), 0.0, 1.0);
    porosity = p * (1.0 - isSSS);
    subsurface = s * isSSS;

    float a = clamp(spec.a, 0.0, 1.0) * 255.0;
    a = clamp(a / 254.0, 0.0, 254);
    emissive = clamp(a / 254.0, 0.0, 1.0);
}

float D_GGX(float NoH, float roughness)
{
    float a  = max(roughness * roughness, 1e-4); // alpha
    float a2 = a * a;
    float d  = NoH * NoH * (a2 - 1.0) + 1.0;
    return a2 / (3.14159265 * d * d);
}

vec3 ndcToViewPos(vec3 ndc)
{
    vec4 v = gbufferProjectionInverse * vec4(ndc, 1.0);
    return v.xyz / max(v.w, 1e-6);
}

float pow5(float x)
{
    float x2 = x * x;
    return x2 * x2 * x;
}

// Dielectric Schlick Fresnel using scalar F0 (0..1)
vec3 fresnelSchlick(float cosTheta, float F0)
{
    cosTheta = clamp(cosTheta, 0.0, 1.0);
    float oneMinusCos = 1.0 - cosTheta;
    return vec3(F0) + (vec3(1.0) - vec3(F0)) * pow5(oneMinusCos);
}

float G_BiMS(float WoN, float WiN, float roughness)
{
    float rou2 = max(roughness * roughness, 1e-4);

    float cos2I = WiN * WiN;
    float sin2I = 1.0 - cos2I;
    float tan2I = max(sin2I / cos2I, 1e-6);
    float lambdGi = (sqrt(1.0 + rou2 * tan2I) - 1.0) / 2.0;

    float cos2O = WoN * WoN;
    float sin2O = 1.0 - cos2O;
    float tan2O = max(sin2O / cos2O, 1e-6);
    float lambdGo = (sqrt(1.0 + rou2 * tan2O) - 1.0) / 2.0;

    return 1.0 / (1.0 + lambdGi + lambdGo);
}

vec3 SrgbToLinear(vec3 c)
{
    return pow(max(c, vec3(0.0)), vec3(2.2));
}

vec3 LinearToSrgb(vec3 c)
{
    return pow(max(c, vec3(0.0)), vec3(1.0 / 2.2));
}

vec4 getNoise(vec2 coord)
{
	ivec2 screenCoord = ivec2(coord * vec2(viewWidth, viewHeight));
	const int noiseRes = 64;
	ivec2 noiseCoord = screenCoord % noiseRes;
	return texelFetch(noisetex, noiseCoord, 0);
}

vec3 getShadow(vec3 shadowScreenPos)
{
	float transparentShadow = step(shadowScreenPos.z, texture(shadowtex0, shadowScreenPos.xy).r);
	if (transparentShadow == 1.0)
	{
		return vec3(1.0);
	}
	float opaqueShadow = step(shadowScreenPos.z, texture(shadowtex1, shadowScreenPos.xy).r);
	if (opaqueShadow == 0.0)
	{
		return vec3(0.0);
	}
	vec4 shadowColor = texture(shadowcolor0, shadowScreenPos.xy);
	return shadowColor.rgb * (1.0 - shadowColor.a);
}

vec3 getSoftShadow(vec3 shadowScreenPos)
{
	vec3 shadowAccum = vec3(0.0);
	float weightSum = 0.0, count = 0.0;
	//float sigma = 16;//max(float(SHADOW_RANGE) * 0.5, 1.0);

	float noise = getNoise(lmtexcoord.xy).r;
	//float theta, cosTheta, sinTheta;
	float theta = noise * radians(60.0);
	float cosTheta = cos(theta);
	float sinTheta = sin(theta);
	mat2 rotation = mat2(cosTheta, -sinTheta, sinTheta, cosTheta);

	//mat2 rotation;

	for (int x = -SHADOW_RANGE; x < SHADOW_RANGE; x++)
	{
		for (int y = -SHADOW_RANGE; y < SHADOW_RANGE; y++)
		{
			vec2 tap = vec2(x, y);

			

			tap = rotation * tap;
			float w = exp(-dot(tap, tap) / (2.0 * SIGMA * SIGMA));

			vec2 offset = tap * (float(SHADOW_RADIUS) / float(SHADOW_RANGE));
			offset /= float(shadowMapResolution);
			vec3 offsetShadowScreenPos = shadowScreenPos + vec3(offset, 0.0);
			offsetShadowScreenPos.xy = clamp(offsetShadowScreenPos.xy, 0.0, 1.0);

			shadowAccum += getShadow(offsetShadowScreenPos) * w;
			weightSum += w;
		}
	}

	return shadowAccum / max(weightSum, 1e-6);
}

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 outcolor;
void main()
{
    vec4 albedo = texture(gtexture, lmtexcoord.xy) * color;
    if (albedo.a < 0.00001)
	{
		discard;
	}

    albedo.rgb = SrgbToLinear(albedo.rgb);
    vec4 norInf = texture(normals, lmtexcoord.xy);
    vec4 speInf = texture(specular, lmtexcoord.xy);

    vec3 tangentNormal = vec3(norInf.x * 2.0 - 1.0, -(norInf.y * 2.0 - 1.0), 0.0);
    tangentNormal.z = sqrt(max(1.0 - dot(tangentNormal.xy, tangentNormal.xy), 0.0));
    tangentNormal = normalize(tangentNormal);

    float occlusion = norInf.z;
    float height = norInf.w;
    
    float perceptualSmoothness = speInf.r;
    float roughness = pow(1.0 - perceptualSmoothness, 2.0);

    float f0 = speInf.g;
    
    int metalId = int(f0 * 255.0 + 0.5);
    #ifdef FORCIBLY_ENABLE_PBR
    #ifdef MC_TEXTURE_FORMAT_LAB_PBR
        float is_iron = float(material_id == BLOCK_IRON);
        metalId = int(mix(metalId, 230, is_iron));
        float is_gold = float(material_id == BLOCK_GOLD);
        metalId = int(mix(metalId, 231, is_gold));
        float is_copper = float(material_id == BLOCK_COPPER);
        metalId = int(mix(metalId, 234, is_copper));
    #endif
    #endif
    

    int metalIndex = metalId - METAL_ID_BASE;
    int metalInRange = int(metalIndex >= 0 && metalIndex < METAL_COUNT);
    int metalSafeIndex = metalIndex * metalInRange; // out of range -> 0 (Iron default)
    vec3 metalN = METAL_N[metalSafeIndex];
    vec3 metalK = METAL_K[metalSafeIndex];

    float porosity;
    float subsurface;
    float emissive;
    decodeLabPBRExtras(speInf, porosity, subsurface, emissive);

    vec2 screenUV = gl_FragCoord.xy / vec2(viewWidth, viewHeight);
    float depth = gl_FragCoord.z;
    vec3 ndcPos = vec3(screenUV * 2.0 - 1.0, depth * 2.0 - 1.0);
    vec3 viewPos = ndcToViewPos(ndcPos);
    vec3 feetPlayerPos = (gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz;
	vec3 shadowViewPos = (shadowModelView * vec4(feetPlayerPos, 1.0)).xyz;
	vec4 shadowClipPos = shadowProjection * vec4(shadowViewPos, 1.0);

    shadowClipPos.z -= 0.001;
	shadowClipPos.xyz = distortShadowClipPos(shadowClipPos.xyz);

	vec3 shadowNDCPos = shadowClipPos.xyz / shadowClipPos.w;
	vec3 shadowScreenPos = shadowNDCPos * 0.5 + 0.5;
	shadowScreenPos = clamp(shadowScreenPos, 0.0, 1.0);

    //float shadow = step(shadowScreenPos.z, texture(shadowtex0, shadowScreenPos.xy).r);
    vec3 shadow = getSoftShadow(shadowScreenPos);

    vec3 N = normalize(mat3(normalize(TBN[0]), normalize(TBN[1]), normalize(TBN[2])) * tangentNormal);
    vec3 V = normalize(-viewPos);
    //vec3 L = normalize(sunVec);
    vec3 L = normalize(shadowLightPosition);
    
    vec3 H = normalize(V + L);

    #ifndef MC_TEXTURE_FORMAT_LAB_PBR
        #ifdef FORCIBLY_ENABLE_VANILLA_PBR
            N = normalize(TBN[2]);
            f0 = 0.1;
            roughness = 2.0;
        #endif
    #endif
    roughness = mix (roughness, 2.0 * roughness, wetness);
    f0 = mix (f0 * 0.5, f0, wetness);
    float ifPorosity = float(material_id == BLOCK_POROSITY);
    porosity = mix(porosity, 1.0, ifPorosity);

    float NoV = clamp(dot(N, V), 0.0, 1.0);
    float NoL = clamp(dot(N, L), 0.0, 1.0);
    float NoH = clamp(dot(N, H), 0.0, 1.0);
    float VoH = clamp(dot(V, H), 0.0, 1.0);

    vec3 F = vec3(1.0);

    #ifndef CLOSE_PBR_AND_OPEN_PHONG

    #ifdef FRESNEL
        // Metal IDs 230..237 in speInf.g are treated as conductors; otherwise treat speInf.g as dielectric F0.
        float F0_dielectric = clamp(f0, 0.0, 1.0);
        vec3 F_metal = fresnelConductorComplex(VoH, metalN, metalK);
        vec3 F_dielectric = fresnelSchlick(VoH, F0_dielectric);
        F = mix(F_dielectric, F_metal, float(metalInRange));
    #else
        float F0_dielectric = clamp(f0, 0.0, 1.0);
        F = fresnelSchlick(VoH, F0_dielectric);;
    #endif

    //D in here
    float D = D_GGX(NoH, roughness);

    //G in here
    float G = G_BiMS(NoV, NoL, roughness);
    
    //brdf in here
    vec3 specBRDF = (D * G) * F / max(4.0 * NoV * NoL, 1e-6);

    float metallic = float(metalInRange);
    float metal_conpensate = 0.0;// mix(0.0, VANILLA_METAL_CONPENSATE * 0.093, metallic);
    vec3 kd = (vec3(1.0) - F + metal_conpensate) * (1.0 - metallic + metal_conpensate);
    vec3 diffuseBRDF = kd * albedo.rgb * (1.0 / 3.14159265);

    vec3 direct = SunOrMoonLight[int(SunOrMoon)] * NoL * (diffuseBRDF * 1.0 * DIFFUSE_BRDF + specBRDF * 1.0) * shadow;// * 2.0;

    vec3 lm = SrgbToLinear(texture(lightmap, lmtexcoord.zw).rgb);

    // Simple hemisphere ambient (sky vs ground) to avoid pitch-black shading.
    float hemi = clamp(N.y * 0.5 + 0.5, 0.0, 1.0);
    vec3 ambientHemi = mix(vec3(0.045, 0.040, 0.038), vec3(0.16, 0.18, 0.22), hemi);
    vec3 ambient = albedo.rgb * (ambientHemi * 0.25 + (0.5 + VANILLA_METAL_CONPENSATE) * lm * 0.5);

    vec2 dir_amb = DIR_AMB[metalInRange];

    vec3 radiance = (pow(direct, vec3(dir_amb[0])) * (1.0 - wetness * porosity) + ambient * dir_amb[1]) * clamp(occlusion, 0.0, 1.0);

    radiance += albedo.rgb * emissive;

    outcolor = vec4(LinearToSrgb(radiance), albedo.a);
    //outcolor.rgb += albedo.rgb * VANILLA_METAL_CONPENSATE * 0.5;
    
    #endif

    #ifdef CLOSE_PBR_AND_OPEN_PHONG

    vec3 lm = SrgbToLinear(texture(lightmap, lmtexcoord.zw).rgb);

    // Simple hemisphere ambient (sky vs ground) to avoid pitch-black shading.
    float hemi = clamp(N.y * 0.5 + 0.5, 0.0, 1.0);
    vec3 ambientHemi = mix(vec3(0.045, 0.040, 0.038), vec3(0.16, 0.18, 0.22), hemi);
    vec3 ambient = albedo.rgb * (ambientHemi * 0.25 + (0.5 + VANILLA_METAL_CONPENSATE) * lm);

    // Blinn-Phong spec exponent derived from roughness.
    float r = clamp(roughness, 0.02, 1.0);
    float shininess = max(2.0 / (r * r) - 2.0, 1.0);

    // Diffuse (Lambert)
    vec3 diffuse = albedo.rgb * (1.0 / 3.14159265) * NoL * DIFFUSE_BRDF;

    // Specular (normalized Blinn-Phong)
    float blinn = pow(NoH, shininess);
    float norm = (shininess + 8.0) * (1.0 / (8.0 * 3.14159265));

    float metallic = float(metalInRange);
    vec3 specTint = mix(vec3(clamp(f0, 0.0, 1.0)), albedo.rgb, metallic);

    vec3 Fp = vec3(1.0);
    #ifdef FRESNEL
        Fp = fresnelSchlick(VoH, clamp(f0, 0.0, 1.0));
    #endif

    vec3 specularPhong = specTint * Fp * (norm * blinn) * NoL;

    vec3 direct = SunOrMoonLight[int(SunOrMoon)] * (diffuse + specularPhong);

    vec2 dir_amb = DIR_AMB[metalInRange];
    vec3 radiance = (pow(direct, vec3(dir_amb[0])) * (1.0 - wetness * porosity) + ambient * dir_amb[1]) * clamp(occlusion, 0.0, 1.0);
    radiance += albedo.rgb * emissive;

    outcolor = vec4(LinearToSrgb(radiance), albedo.a);

    #endif

    //outcolor = vec4(radiance, albedo.a);
    if (porosity > 0.001)
    {
        //outcolor = vec4(1.0);
        return;
    }
}