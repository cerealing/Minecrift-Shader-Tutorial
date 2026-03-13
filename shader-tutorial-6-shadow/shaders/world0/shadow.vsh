#version 330 compatibility

#include "/lib/distort.glsl"

out vec2 texcoord;
out vec4 glcolor;

void main()
{
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    glcolor = gl_Color;
    //gl_Position = ftransform();
    gl_Position = gl_ProjectionMatrix * gl_ModelViewMatrix * gl_Vertex;
    gl_Position.xyz = distortShadowClipPos(gl_Position.xyz);
}