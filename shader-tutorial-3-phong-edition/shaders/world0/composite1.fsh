
#version 460 compatibility

in vec2 texcoord;

uniform mat4 gbufferPreviousModelView;
uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform sampler2D depthtex0;
uniform sampler2D colortex0;
uniform sampler2D colortex1;

/* RENDERTARGETS: 1 */
layout(location = 1) out vec4 color;

vec3 projectAndDivide(mat4 projectionMatrix, vec3 position)
{
    vec4 projected = projectionMatrix * vec4(position, 1.0);
    float invW = 1.0 / max(projected.w, 1e-6);
    return projected.xyz * invW;
}

void main()
{
    float depth = texture(depthtex0, texcoord).r;
    vec3 ndcPos = vec3(texcoord * 2.0 - 1.0, depth * 2.0 - 1.0);

    vec3 viewPos = projectAndDivide(gbufferProjectionInverse, ndcPos);

    vec4 worldPos = gbufferModelViewInverse * vec4(viewPos, 1.0);
    vec4 previousViewPos = gbufferPreviousModelView * worldPos;
    vec4 previousClipPos = gbufferProjection * previousViewPos;
    float previousInvW = 1.0 / max(previousClipPos.w, 1e-6);
    vec3 previousNDCPos = previousClipPos.xyz * previousInvW;
    vec2 previousUv = previousNDCPos.xy * 0.5 + 0.5;

	vec4 currentColor = texture(colortex0, texcoord);

    vec2 previousUvClamped = clamp(previousUv, 0.0, 1.0);
    vec4 historyColor = texture(colortex1, previousUvClamped);

    float inBounds = step(0.0, previousUv.x) * step(previousUv.x, 1.0) * step(0.0, previousUv.y) * step(previousUv.y, 1.0);
    float hasDepth = 1.0 - step(0.999999, depth);
    float valid = inBounds * hasDepth;

    float taaAlpha = 0.9;
    vec4 taaColor = mix(currentColor, historyColor, taaAlpha * valid);

	color = taaColor;
}
