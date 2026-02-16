#version 460 compatibility

#include "/lib/blocks.glsl"
#include "/lib/settings.glsl"

in vec2 mc_midTexCoord;
in vec2 mc_Entity;

out vec4 color;
out vec4 lmtexcoord;

uniform int worldTime;
uniform vec3 cameraPosition;
uniform float frameTimeCounter;
uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;


#define diagonal3(m) vec3((m)[0].x, (m)[1].y, (m)[2].z )
#define projMAD(m, v) (diagonal3(m) * (v) + (m)[3].xyz)
vec4 toClipSpace3(vec3 viewSpacePosition)
{
    return vec4(projMAD(gbufferProjection, viewSpacePosition), -viewSpacePosition.z);
}

vec2 calGroundWave(in vec3 position)
{
    float magnitude = (sin(dot(vec4(frameTimeCounter, position + cameraPosition), vec4(1.0, 0.0123, 0.0145, 0.0167))) * 0.5 + 0.75) * 0.12345;
    vec2 wave = (sin(worldTime * WAVE_SPEED + position.xz + position.y * 0.1) + 0.1) * magnitude;
    return wave;
}

vec3 calGroundMove(in vec3 position)
{
    vec2 wave = calGroundWave(position);
    float waveY = length(wave);
    return vec3(wave.x, -waveY, wave.y) * WAVE_STRENGTH;  
}

vec3 calAirWave(in vec3 position)
{
    float magnitude = (sin(dot(vec4(frameTimeCounter, position + cameraPosition), vec4(1.0, 0.01, 0.01, 0.01))) * 0.5 + 0.75) * 0.12345;
    vec3 wave = (sin(worldTime * WAVE_SPEED * vec3(0.0678, 0.234, 0.0345) * 5.77 + position + cameraPosition)) * magnitude;
    return wave; 
}

vec3 calAirWaveMove(in vec3 position)
{
    vec3 move = calAirWave(position) * vec3(0.5, 0.2, 0.5);
    return move * WAVE_STRENGTH;  
}

void main()
{
    vec3 position = gl_Vertex.xyz;
    //vec3 position = mat3(gl_ModelViewMatrix) * vec3(gl_Vertex) + gl_ModelViewMatrix[3].xyz;
    color = gl_Color;
    lmtexcoord.xy = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    vec2 lmcoord = gl_MultiTexCoord1.xy / 240.0;
    lmtexcoord.zw = lmcoord;

    bool if_wave_ground_plane = (mc_Entity.x == BLOCK_GRASS_TALL_LOWER) || (mc_Entity.x == BLOCK_GROUND_WAVING) || (mc_Entity.x == BLOCK_GRASS_SHORT) || (mc_Entity.x == BLOCK_SAPLING) || (mc_Entity.x == BLOCK_GROUND_WAVING_VERTICAL);
    bool if_wave_air_plane = (mc_Entity.x == BLOCK_GRASS_TALL_UPPER) || (mc_Entity.x == BLOCK_AIR_WAVING);
    bool if_hight = gl_MultiTexCoord0.t < mc_midTexCoord.t;
    bool if_ground_wave = if_hight && if_wave_ground_plane;
    vec3 wave_move = if_ground_wave ? calGroundMove(position) : vec3(0.0);
    wave_move = if_wave_air_plane ? calAirWaveMove(position) : wave_move;

    position += wave_move;
    position = mat3(gbufferModelView) * vec3(position) + gbufferModelView[3].xyz;

    gl_Position = toClipSpace3(position);
}