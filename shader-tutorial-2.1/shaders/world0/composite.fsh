
#version 460 compatibility

in vec2 texcoord;

uniform sampler2D colortex0;

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 color;

void main()
{
	vec4 albedo = texture(colortex0, texcoord);
	
	color = albedo;
}
