#version 460 compatibility

in vec2 mc_Entity;

out float entityId;
out vec2 texcoord;
out vec4 glcolor;

void main() {
	gl_Position = ftransform();
	texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
	glcolor = gl_Color;
    entityId = mc_Entity.x;
}