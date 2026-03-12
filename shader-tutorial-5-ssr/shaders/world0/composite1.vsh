#version 460 compatibility

flat out float SunOrMoon;
out vec2 texcoord;

uniform float sunElevation;

void main()
{
	gl_Position = gl_Vertex * 2.0 - 1.0;
	gl_Position = ftransform();

	SunOrMoon = float(sunElevation > 1e-5);

	texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
}
