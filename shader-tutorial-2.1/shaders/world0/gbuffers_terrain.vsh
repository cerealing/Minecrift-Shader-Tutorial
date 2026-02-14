#version 460 compatibility

#include "/lib/blocks.glsl"

in vec2 mc_midTexCoord;
in vec2 mc_Entity;

out vec4 color;
out vec4 lmtexcoord;

uniform int worldTime;
uniform vec3 cameraPosition;
uniform float frameTimeCounter;
uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;

#define diagonal3(m) vec3((m)[0].x, (m)[1].y, (m)[2].z )
#define projMAD(m, v) (diagonal3(m) * (v) + (m)[3].xyz)
vec4 toClipSpace3(vec3 viewSpacePosition)
{
    return vec4(projMAD(gl_ProjectionMatrix, viewSpacePosition), -viewSpacePosition.z);
}

void main()
{
    vec3 position = gl_Vertex.xyz;
    //vec3 position = mat3(gl_ModelViewMatrix) * vec3(gl_Vertex) + gl_ModelViewMatrix[3].xyz;
    color = gl_Color;
    lmtexcoord.xy = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    vec2 lmcoord = gl_MultiTexCoord1.xy / 240.0;
    lmtexcoord.zw = lmcoord;

    float if_Wave_Plane = mc_Entity.x == BLOCK_GRASS_SHORT ? 1.0 : 0.0;
    float if_Hight = gl_MultiTexCoord0.t < mc_midTexCoord.t ? 1.0 : 0.0;
    float if_Wave = if_Wave_Plane * if_Hight;
    float wave_Strength = sin((position + cameraPosition).x * 0.1 + (position + cameraPosition).y * 0.1 + worldTime * 0.1) * 0.1;
    position += if_Wave * wave_Strength;
    position = mat3(gl_ModelViewMatrix) * vec3(position) + gl_ModelViewMatrix[3].xyz;

    gl_Position = toClipSpace3(position);
}