#version 460 compatibility

out vec2 texcoord;

void main()
{
	gl_Position = gl_Vertex * 2.0 - 1.0;
	texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
}
