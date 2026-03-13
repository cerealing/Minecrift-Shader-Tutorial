#version 460 compatibility

const bool colortex4Clear = false;
const bool colortex5Clear = false;

in vec2 texcoord;

uniform vec2 texelSize;
uniform sampler2D colortex0;

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 color;

void main()
{
	vec2 tc = gl_FragCoord.xy * texelSize;
	vec4 albedo = texture2D(colortex0, tc);

	color = albedo;
}
